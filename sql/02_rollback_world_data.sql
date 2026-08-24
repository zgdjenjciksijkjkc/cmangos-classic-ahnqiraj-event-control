-- Roll back only the static rows changed by 01_apply_world_data.sql.
-- Run while mangosd is stopped.

USE classicmangos;

UPDATE game_event AS current_event
JOIN aq_backup_20260804_game_event AS backup_event
  ON backup_event.entry = current_event.entry
SET current_event.schedule_type = backup_event.schedule_type
WHERE current_event.entry BETWEEN 120 AND 127;

DELETE FROM game_event_gameobject
WHERE guid IN (49390,49391,49392,66334,66335,66336);

INSERT INTO game_event_gameobject
SELECT * FROM aq_backup_20260804_game_event_gameobject
WHERE guid IN (49390,49391,49392,66334,66335,66336);

DELETE FROM gameobject_addon
WHERE guid IN (49390,49391,49392,66334,66335,66336);

INSERT INTO gameobject_addon
SELECT * FROM aq_backup_20260804_gameobject_addon
WHERE guid IN (49390,49391,49392,66334,66335,66336);

UPDATE gameobject_template AS current_template
JOIN aq_backup_20260804_gameobject_template AS backup_template
  ON backup_template.entry = current_template.entry
SET current_template.data0 = backup_template.data0
WHERE current_template.entry IN (176146,176147,176148,180898,180899,180904);

SELECT guid, event
FROM game_event_gameobject
WHERE guid IN (49390,49391,49392,66334,66335,66336)
ORDER BY guid, event;

-- Character world_state is backed up separately by AQ事件控制.ps1. Restore
-- the corresponding autobak\AQ事件控制\AQ_state_*.sql file if needed.
