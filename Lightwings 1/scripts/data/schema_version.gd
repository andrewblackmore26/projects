class_name SchemaVersion
extends RefCounted
## Single shared constant for both the save envelope version (SaveService)
## and the campaign gameplay schema version (CampaignState.GAMEPLAY_VERSION).
## v0.2 had the literal `3` written separately in several places; P5b's
## save-schema-4 work replaces every one of those literals with this.
const CURRENT: int = 4
