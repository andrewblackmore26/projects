class_name ShipCommand
extends RefCounted

var movement: Vector2 = Vector2.ZERO
var aim: Vector2 = Vector2.UP
var fire: bool = false
var secondaries: Array[bool] = [false, false, false]
var ability_primary: bool = false
var ability_secondary: bool = false
var secondary_held: bool = false
var dash: bool = false
