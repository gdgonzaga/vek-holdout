## Test double for a wired map's ItemsLayer. WorldItem.spawn_at parents every item
## under the node registered in the "items_layer" group and refuses to spawn when
## there is none, so any suite that spawns items without a Map needs one of these.
## ColonySandbox already provides one as `items_layer`. Plain script, never a suite.


## Adds a fresh in-tree layer (auto-freed with the test) and returns it.
static func add_to(suite: GdUnitTestSuite) -> Node3D:
	var layer := Node3D.new()
	layer.name = "ItemsLayer"
	layer.add_to_group(&"items_layer")
	suite.auto_free(layer)
	suite.add_child(layer)
	return layer
