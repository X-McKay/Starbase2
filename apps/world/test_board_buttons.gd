extends SceneTree
const Board=preload("res://command_board.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for large in [false,true]:
		for width in [640,960,1280]:
			root.size=Vector2i(width,800)
			root.content_scale_size=Vector2i(width,800)
			var board=Board.new(); board.large_text=large
			root.add_child(board); board.timer.stop(); board.show()
			var row=HFlowContainer.new(); board.runs.add_child(row)
			var actions: Array[Button]=[]
			for title in ["Findings","Stop observation","Pause","Remove","Restore","Resume","Latest findings","Source","Approve","Reject","Revoke"]:
				actions.append(board.button(row,title,func(): pass))
			for frame in range(3): await process_frame
			for action in actions:
				var font=action.get_theme_font("font")
				var text_width=font.get_string_size(action.text,HORIZONTAL_ALIGNMENT_LEFT,-1,action.get_theme_font_size("font_size")).x
				var style=action.get_theme_stylebox("normal")
				assert(action.size.x >= text_width+style.get_minimum_size().x-2,"Action text clipped: "+action.text)
				assert(action.get_global_rect().end.x <= board.get_viewport_rect().size.x,"Action row overflowed viewport")
			board.queue_free(); await process_frame
	print("Board buttons passed: all action labels fit at 640/960/1280 widths, default and large text")
	quit()
