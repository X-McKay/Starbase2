ARG PYTHON_IMAGE
ARG UV_IMAGE
FROM ${UV_IMAGE} AS uv
FROM ${PYTHON_IMAGE}
COPY --from=uv /uv /usr/local/bin/uv
WORKDIR /app
ENV UV_PROJECT_ENVIRONMENT=/app/.venv UV_LINK_MODE=copy
COPY pyproject.toml uv.lock ./
RUN test "$(python --version)" = "Python 3.12.13" && uv --version | grep -Eq '^uv 0\.12\.7( \([^)]*\))?$'
RUN uv sync --locked --no-install-project --no-dev --no-cache
COPY services/runtime services/runtime
COPY services/core/src services/core/src
COPY fixtures fixtures
ENV PATH=/app/.venv/bin:$PATH PYTHONPATH=/app/services/runtime PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
USER 10001:10001
ENTRYPOINT ["/app/.venv/bin/python", "-m", "starbase_runtime.worker", "worker"]
