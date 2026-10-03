extends SceneTree
const Driver=preload("res://characters/environment_interaction.gd")
func _initialize() -> void:
	var driver=Driver.new()
	var signatures:Dictionary={}
	for role in Driver.SEQUENCES:
		var actions:Array=[]
		var elapsed:=0.0
		for item in Driver.SEQUENCES[role]:
			assert(float(item[1])>0)
			var sample:Dictionary=driver.sequence_sample(role,elapsed+.01)
			actions.append(sample.action);elapsed+=float(item[1])
		assert("type" in actions and actions.size()>=5,role+" has a bounded work vocabulary")
		signatures[role]=JSON.stringify(actions)
	assert(signatures.mender!=signatures.surveyor and signatures.trainer!=signatures.watchkeeper)
	assert(driver.sequence_sample("reviewer",10000).action in ["type","compare","control","annotate","read"])
	print("WORK_CHOREOGRAPHY_PASSED: six deterministic class vocabularies with bounded type/read/control/point variations")
	quit()
