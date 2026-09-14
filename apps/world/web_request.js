/* Browser-only JSON transport. Cookies and Origin belong to the browser. */
(() => {
  "use strict";
  const permitted = (value) => {
    try {
      const url = new URL(value);
      return url.origin === location.origin && !url.username && !url.password &&
        !url.hash && (url.protocol === "https:" ||
          (url.protocol === "http:" && url.hostname === "127.0.0.1"));
    } catch (_) { return false; }
  };
  window.StarbaseWebTransport = {
    origin: location.origin,
    permitted,
    create(callback) {
      let active = null;
      let generation = 0;
      return {
        get busy() { return active !== null; },
        cancel() {
          if (!active) return;
          const old = active;
          active = null;
          clearTimeout(old.timer);
          old.controller.abort();
        },
        request(url, method, body, timeoutMs, limit) {
          if (active || !permitted(url) || !["GET", "POST"].includes(method) ||
              !Number.isFinite(timeoutMs) || timeoutMs <= 0 ||
              !Number.isSafeInteger(limit) || limit <= 0) return false;
          const item = {id: ++generation, controller: new AbortController(), timer: null};
          active = item;
          const finish = (result, code = 0, payload = "") => {
            if (active !== item) return;
            active = null;
            clearTimeout(item.timer);
            callback(JSON.stringify([result, code, payload]));
          };
          item.timer = setTimeout(() => {
            item.controller.abort();
            finish("timeout");
          }, timeoutMs);
          (async () => {
            try {
              const response = await fetch(url, {
                method, credentials: "same-origin", redirect: "error", mode: "same-origin",
                cache: "no-store", signal: item.controller.signal,
                ...(method === "POST" ? {headers: {"Content-Type": "application/json"}, body} : {}),
              });
              if (response.redirected || response.type === "opaqueredirect") {
                item.controller.abort();
                finish("connection_error");
                return;
              }
              const reader = response.body?.getReader();
              const chunks = [];
              let size = 0;
              if (reader) {
                for (;;) {
                  const {value, done} = await reader.read();
                  if (done) break;
                  size += value.byteLength;
                  if (size > limit) {
                    item.controller.abort();
                    finish("body_limit");
                    return;
                  }
                  chunks.push(value);
                }
              }
              const bytes = new Uint8Array(size);
              let offset = 0;
              for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
              let binary = "";
              for (let offset = 0; offset < bytes.length; offset += 8192) {
                binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
              }
              finish("success", response.status, btoa(binary));
            } catch (_) { finish("connection_error"); }
          })();
          return true;
        },
      };
    },
  };
})();
