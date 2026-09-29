class_name EventBus
extends RefCounted
## Decoupled signal hub. Systems emit, UI and other systems listen.

signal year_advanced(age: int)
signal state_changed
signal log_added(entry: Dictionary)
signal event_queued(event_instance: Dictionary)
signal system_notice(kind: String, payload: String)
signal character_died(summary: Dictionary)
signal new_life_started
signal level_up(new_level: int)
signal skill_learned(skill_id: String)
signal skill_level_up(skill_id: String, level: int)
signal skill_evolved(from_id: String, to_id: String)
signal title_earned(title_id: String)
signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)
signal job_changed(job_id: String)
signal relationship_changed(npc_id: String)
signal money_changed(delta: float)
signal disease_added(disease_id: String)
signal child_born(npc_id: String)
signal crime_committed(crime_id: String)
signal achievement_unlocked(achievement_id: String)
signal action_performed(action_id: String)
