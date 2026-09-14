extends Node

const MARKER := "starbase-web-probe-ready"

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	await RenderingServer.frame_post_draw
	JavaScriptBridge.eval("""
(() => {
  const marker = 'starbase-web-probe-ready';
  const metrics = {marker, postDrawAt: performance.now(), href: location.href};
  window.starbaseWebProbe = metrics;
  document.documentElement.dataset.starbaseWebProbe = marker;
  const visible = document.createElement('p');
  visible.id = 'starbase-web-probe-metrics';
  visible.style.cssText = 'position:fixed;z-index:2147483647;left:8px;bottom:8px;margin:0;padding:6px;background:#fff;color:#111;font:12px monospace';
  visible.textContent = marker + ' post-draw ' + Math.round(metrics.postDrawAt) + 'ms';
  document.body.append(visible);
  performance.mark(marker);
  requestAnimationFrame(() => {
    metrics.presentationProxyAt = performance.now();
    visible.textContent += ' presentation-proxy ' + Math.round(metrics.presentationProxyAt) + 'ms';
  });
})();
""", true)
