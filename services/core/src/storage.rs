//! Small synchronous store boundary. SQLite is development-only; PostgreSQL owns production.
//! Both drivers return the same typed scalar rows. Application SQL is explicit, not rewritten.
use rusqlite::types::{FromSql, ToSql, ToSqlOutput, Value, ValueRef};
use sqlx::{Connection as _, Row as _, TypeInfo as _};
use std::sync::{Mutex, OnceLock};

type Result<T> = rusqlite::Result<T>;
fn error(e: sqlx::Error) -> rusqlite::Error {
    rusqlite::Error::ToSqlConversionFailure(Box::new(e))
}
fn wait<F: std::future::Future>(future: F) -> F::Output {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    let runtime = RT.get_or_init(|| tokio::runtime::Runtime::new().expect("storage runtime"));
    if tokio::runtime::Handle::try_current().is_ok() {
        tokio::task::block_in_place(|| runtime.block_on(future))
    } else {
        runtime.block_on(future)
    }
}
pub fn parameter(v: &dyn ToSql) -> Value {
    match v.to_sql().expect("supported store parameter") {
        ToSqlOutput::Owned(v) => v,
        ToSqlOutput::Borrowed(v) => v.into(),
        _ => panic!("unsupported store parameter"),
    }
}
#[macro_export]
macro_rules! parameters {
    ($($p:expr),* $(,)?) => { vec![$($crate::storage::parameter(&$p)),*] };
}
pub enum Database {
    Sqlite(rusqlite::Connection),
    Postgres(Mutex<sqlx::PgConnection>),
}
pub struct Row(Vec<Value>);
impl Row {
    pub fn get<I: TryInto<usize>, T: FromSql>(&self, index: I) -> Result<T> {
        let index = index
            .try_into()
            .map_err(|_| rusqlite::Error::InvalidColumnIndex(0))?;
        let v = self
            .0
            .get(index)
            .ok_or(rusqlite::Error::InvalidColumnIndex(index))?;
        T::column_result(ValueRef::from(v)).map_err(|e| {
            rusqlite::Error::FromSqlConversionFailure(index, v.data_type(), Box::new(e))
        })
    }
}
impl Database {
    pub fn postgres(url: &str) -> Result<Self> {
        let mut db = wait(async {
            tokio::time::timeout(
                std::time::Duration::from_secs(10),
                sqlx::PgConnection::connect(url),
            )
            .await
        })
        .map_err(|_| rusqlite::Error::InvalidQuery)?
        .map_err(error)?;
        // A single authoritative core is intentional. Fail a competing startup instead of
        // admitting multi-writer races in the existing core state machine.
        let locked: bool =
            wait(sqlx::query_scalar("SELECT pg_try_advisory_lock(782934220)").fetch_one(&mut db))
                .map_err(error)?;
        if !locked {
            return Err(rusqlite::Error::InvalidQuery);
        }
        wait(
            sqlx::raw_sql(
                "SET statement_timeout='10s'; SET lock_timeout='5s'; SET search_path=public",
            )
            .execute(&mut db),
        )
        .map_err(error)?;
        Ok(Self::Postgres(Mutex::new(db)))
    }
    pub fn dialect(&self, sqlite: &'static str, postgres: &'static str) -> &'static str {
        match self {
            Self::Sqlite(_) => sqlite,
            Self::Postgres(_) => postgres,
        }
    }
    fn pg_query<'a>(
        sql: &'static str,
        params: Vec<Value>,
    ) -> sqlx::query::Query<'a, sqlx::Postgres, sqlx::postgres::PgArguments> {
        let mut query = sqlx::query(sql);
        for v in params {
            query = match v {
                Value::Null => query.bind(None::<String>),
                Value::Text(s) => query.bind(s),
                Value::Integer(n) => query.bind(n),
                Value::Real(n) => query.bind(n),
                Value::Blob(b) => query.bind(b),
            };
        }
        query
    }
    pub fn execute(&self, sql: &'static str, params: Vec<Value>) -> Result<usize> {
        match self {
            Self::Sqlite(db) => db.execute(sql, rusqlite::params_from_iter(params)),
            Self::Postgres(db) => {
                wait(Self::pg_query(sql, params).execute(&mut *db.lock().unwrap()))
                    .map(|r| r.rows_affected() as usize)
                    .map_err(error)
            }
        }
    }
    pub fn execute_batch(&self, sql: &'static str) -> Result<()> {
        match self {
            Self::Sqlite(db) => db.execute_batch(sql),
            Self::Postgres(db) => wait(sqlx::raw_sql(sql).execute(&mut *db.lock().unwrap()))
                .map(|_| ())
                .map_err(error),
        }
    }
    fn rows(&self, sql: &'static str, params: Vec<Value>) -> Result<Vec<Row>> {
        match self {
            Self::Sqlite(db) => {
                let mut s = db.prepare(sql)?;
                let count = s.column_count();
                s.query_map(rusqlite::params_from_iter(params), |r| {
                    (0..count)
                        .map(|i| r.get(i))
                        .collect::<Result<Vec<Value>>>()
                        .map(Row)
                })?
                .collect()
            }
            Self::Postgres(db) => {
                let rows = wait(Self::pg_query(sql, params).fetch_all(&mut *db.lock().unwrap()))
                    .map_err(error)?;
                rows.into_iter()
                    .map(|r| {
                        r.columns()
                            .iter()
                            .enumerate()
                            .map(|(i, c)| {
                                use sqlx::Column;
                                let value = match c.type_info().name() {
                                    "INT8" => r
                                        .try_get::<Option<i64>, _>(i)
                                        .map(|v| v.map(Value::Integer)),
                                    "FLOAT8" => {
                                        r.try_get::<Option<f64>, _>(i).map(|v| v.map(Value::Real))
                                    }
                                    "BOOL" => r
                                        .try_get::<Option<bool>, _>(i)
                                        .map(|v| v.map(|b| Value::Integer(i64::from(b)))),
                                    _ => r
                                        .try_get::<Option<String>, _>(i)
                                        .map(|v| v.map(Value::Text)),
                                };
                                value.map(|v| v.unwrap_or(Value::Null)).map_err(error)
                            })
                            .collect::<Result<Vec<Value>>>()
                            .map(Row)
                    })
                    .collect()
            }
        }
    }
    pub fn query_row<T>(
        &self,
        sql: &'static str,
        params: Vec<Value>,
        f: impl FnOnce(&Row) -> Result<T>,
    ) -> Result<T> {
        let rows = self.rows(sql, params)?;
        f(rows.first().ok_or(rusqlite::Error::QueryReturnedNoRows)?)
    }
    pub fn prepare<'a>(&'a self, sql: &'static str) -> Result<Statement<'a>> {
        Ok(Statement { db: self, sql })
    }
    pub fn transaction(&mut self) -> Result<Transaction<'_>> {
        self.execute_batch(self.dialect("BEGIN IMMEDIATE", "BEGIN"))?;
        Ok(Transaction {
            db: self,
            committed: false,
        })
    }
}
pub struct Statement<'a> {
    db: &'a Database,
    sql: &'static str,
}
impl Statement<'_> {
    pub fn query_map<T>(
        &mut self,
        params: Vec<Value>,
        f: impl FnMut(&Row) -> Result<T>,
    ) -> Result<std::vec::IntoIter<Result<T>>> {
        Ok(self
            .db
            .rows(self.sql, params)?
            .iter()
            .map(f)
            .collect::<Vec<_>>()
            .into_iter())
    }
}
pub struct Transaction<'a> {
    db: &'a Database,
    committed: bool,
}
impl std::ops::Deref for Transaction<'_> {
    type Target = Database;
    fn deref(&self) -> &Database {
        self.db
    }
}
impl Transaction<'_> {
    pub fn commit(mut self) -> Result<()> {
        self.db.execute_batch("COMMIT")?;
        self.committed = true;
        Ok(())
    }
}
impl Drop for Transaction<'_> {
    fn drop(&mut self) {
        if !self.committed {
            let _ = self.db.execute_batch("ROLLBACK");
        }
    }
}
