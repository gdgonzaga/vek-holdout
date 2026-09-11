extends Job
class_name FetchEquipmentJob
## Job subclass carrying equipment-fetch metadata (ARCH equipment.md).
## Created exclusively by FetchEquipmentJobDef.create_job(); EquipmentAudit posts
## these to the JobBoard when a colonist's desired slot is unfulfilled and the item
## exists in colony storage. The two extra fields are not present on the base Job
## so the base class is not polluted with equipment-specific state.

## Equipment slot this job will fill (Equipment.SLOT_* constant).
var target_slot: String = ""

## ItemDef.id of the item to fetch from storage and equip.
var target_item_id: String = ""

## True if this job was generated automatically to fulfill a tool requirement for labor,
## rather than a player-configured desired loadout in Equipment._desired_slots.
var is_labor_intercept: bool = false
