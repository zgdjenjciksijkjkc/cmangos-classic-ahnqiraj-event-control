-- CMaNGOS Classic / classicmangos
-- AQ gong-to-event-123 static world-data preparation
-- Run only while mangosd is stopped. The statements are idempotent.

USE classicmangos;

-- Pre-check
SELECT entry, schedule_type, description
FROM game_event
WHERE entry BETWEEN 120 AND 124
ORDER BY entry;

SELECT guid, event
FROM game_event_gameobject
WHERE guid IN (49390,49391,49392,66334,66335,66336)
ORDER BY guid, event;

-- Narrow, persistent backup used by 02_rollback_world_data.sql.
CREATE TABLE IF NOT EXISTS aq_backup_20260804_game_event LIKE game_event;
INSERT IGNORE INTO aq_backup_20260804_game_event
SELECT * FROM game_event WHERE entry BETWEEN 120 AND 127;

CREATE TABLE IF NOT EXISTS aq_backup_20260804_game_event_gameobject
LIKE game_event_gameobject;
INSERT IGNORE INTO aq_backup_20260804_game_event_gameobject
SELECT * FROM game_event_gameobject
WHERE guid IN (49390,49391,49392,66334,66335,66336);

CREATE TABLE IF NOT EXISTS aq_backup_20260804_gameobject_addon
LIKE gameobject_addon;
INSERT IGNORE INTO aq_backup_20260804_gameobject_addon
SELECT * FROM gameobject_addon
WHERE guid IN (49390,49391,49392,66334,66335,66336);

CREATE TABLE IF NOT EXISTS aq_backup_20260804_gameobject_template
LIKE gameobject_template;
INSERT IGNORE INTO aq_backup_20260804_gameobject_template
SELECT * FROM gameobject_template
WHERE entry IN (176146,176147,176148,180898,180899,180904);

-- WorldState, not the calendar, owns AQ phases 120-127.
UPDATE game_event
SET schedule_type = 0
WHERE entry BETWEEN 120 AND 127;

-- The verified closed gate group exists through event 122 and despawns when
-- the core switches to event 123, removing the visual door and collision.
DELETE FROM game_event_gameobject
WHERE guid IN (49390,49391,49392,66334,66335,66336);

INSERT INTO game_event_gameobject (guid, event)
VALUES (49390,120),(49391,120),(49392,120),
       (49390,121),(49391,121),(49392,121),
       (49390,122),(49391,122),(49392,122);

UPDATE gameobject_template
SET data0 = 0
WHERE entry IN (180898,180899,180904)
  AND type = 0;

INSERT INTO gameobject_addon (guid, animprogress, state, StringId)
VALUES (49390,100,1,0),(49391,100,1,0),(49392,100,1,0)
ON DUPLICATE KEY UPDATE
    animprogress = VALUES(animprogress),
    state = VALUES(state),
    StringId = VALUES(StringId);

-- Post-check: exactly nine rows, three per phase, and no event-123 binding.
SELECT guid,
       GROUP_CONCAT(event ORDER BY event) AS event_binding,
       COUNT(*) AS binding_count
FROM game_event_gameobject
WHERE guid IN (49390,49391,49392)
GROUP BY guid
ORDER BY guid;

SELECT g.guid, g.id, gt.displayId, ga.state, gt.name
FROM gameobject g
JOIN gameobject_template gt ON gt.entry = g.id
LEFT JOIN gameobject_addon ga ON ga.guid = g.guid
WHERE g.guid IN (49390,49391,49392)
ORDER BY g.guid;

-- Existing event-123 content; this package does not duplicate it.
SELECT 'creature' AS object_type,
       SUM(CASE WHEN event = 123 THEN 1 ELSE 0 END) AS spawned,
       SUM(CASE WHEN event = -123 THEN 1 ELSE 0 END) AS removed
FROM game_event_creature WHERE ABS(event) = 123
UNION ALL
SELECT 'gameobject',
       SUM(CASE WHEN event = 123 THEN 1 ELSE 0 END),
       SUM(CASE WHEN event = -123 THEN 1 ELSE 0 END)
FROM game_event_gameobject WHERE ABS(event) = 123;

SELECT Id, ChatTypeID, Text
FROM broadcast_text
WHERE Id IN (11427,11432)
ORDER BY Id;
