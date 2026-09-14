extends Node
## Opt-in local review metrics, exposed as DOM data without adding game controls.
var samples: Array[float] = []
var first_draw_ms := 0.0
var frames := 0

func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	if not JavaScriptBridge.eval("new URLSearchParams(location.search).get('web-review') === '1'", true):
		set_process(false)
		return
	RenderingServer.frame_post_draw.connect(_first_draw, CONNECT_ONE_SHOT)

func _first_draw() -> void:
	first_draw_ms = float(JavaScriptBridge.eval("performance.now()", true))
	write_metrics()

func _process(delta: float) -> void:
	frames += 1
	if frames > 30 and samples.size() < 600: samples.append(delta * 1000.0)
	if frames % 60 == 0: write_metrics()

func write_metrics() -> void:
	var sorted := samples.duplicate()
	sorted.sort()
	var metrics := {"navigation_to_first_post_draw_ms": first_draw_ms, "sample_count": sorted.size(),
		"frame_interval_median_ms": sorted[sorted.size()/2] if not sorted.is_empty() else 0,
		"frame_interval_p95_ms": sorted[int(sorted.size()*0.95)] if not sorted.is_empty() else 0,
		"texture_memory_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"viewport": str(get_viewport().get_visible_rect().size), "scope": "local process intervals; browser paint and network cold start not certified"}
	JavaScriptBridge.eval("var output=document.getElementById('starbase-world-metrics');if(!output){output=document.createElement('output');output.id='starbase-world-metrics';output.hidden=true;document.body.append(output);}output.textContent=" + JSON.stringify(JSON.stringify(metrics)), true)
