-- Verification for the AQ commendation repair. Read-only except temporary tables.
USE classicmangos;
SET NAMES utf8;

DROP TEMPORARY TABLE IF EXISTS tmp_aq_commendation_expected;
CREATE TEMPORARY TABLE tmp_aq_commendation_expected (
    entry MEDIUMINT UNSIGNED NOT NULL PRIMARY KEY,
    faction_id SMALLINT UNSIGNED NOT NULL,
    reward_value MEDIUMINT NOT NULL,
    prev_quest MEDIUMINT NOT NULL,
    faction_en VARCHAR(64) NOT NULL,
    faction_zh VARCHAR(64) NOT NULL,
    central_npc MEDIUMINT UNSIGNED NOT NULL,
    officer_npc MEDIUMINT UNSIGNED NOT NULL,
    is_initial TINYINT UNSIGNED NOT NULL
) ENGINE=MEMORY DEFAULT CHARSET=utf8;

INSERT INTO tmp_aq_commendation_expected VALUES
(8811,69,5,0,'Darnassus','达纳苏斯',15731,15762,1),
(8819,69,75,0,'Darnassus','达纳苏斯',15731,15762,1),
(8830,69,5,8811,'Darnassus','达纳苏斯',15731,15762,0),
(8831,69,75,8819,'Darnassus','达纳苏斯',15731,15762,0),
(8812,54,5,0,'Gnomeregan Exiles','诺莫瑞根流亡者',15733,15763,1),
(8820,54,75,0,'Gnomeregan Exiles','诺莫瑞根流亡者',15733,15763,1),
(8838,54,5,8812,'Gnomeregan Exiles','诺莫瑞根流亡者',15733,15763,0),
(8839,54,75,8820,'Gnomeregan Exiles','诺莫瑞根流亡者',15733,15763,0),
(8813,47,5,0,'Ironforge','铁炉堡',15734,15764,1),
(8821,47,75,0,'Ironforge','铁炉堡',15734,15764,1),
(8834,47,5,8813,'Ironforge','铁炉堡',15734,15764,0),
(8835,47,75,8821,'Ironforge','铁炉堡',15734,15764,0),
(8814,72,5,0,'Stormwind','暴风城',15735,15766,1),
(8822,72,75,0,'Stormwind','暴风城',15735,15766,1),
(8836,72,5,8814,'Stormwind','暴风城',15735,15766,0),
(8837,72,75,8822,'Stormwind','暴风城',15735,15766,0),
(8815,76,5,0,'Orgrimmar','奥格瑞玛',15736,15765,1),
(8823,76,75,0,'Orgrimmar','奥格瑞玛',15736,15765,1),
(8840,76,5,8815,'Orgrimmar','奥格瑞玛',15736,15765,0),
(8841,76,75,8823,'Orgrimmar','奥格瑞玛',15736,15765,0),
(8816,530,5,0,'Darkspear tribe','暗矛巨魔',15737,15761,1),
(8824,530,75,0,'Darkspear tribe','暗矛巨魔',15737,15761,1),
(8844,530,5,8816,'Darkspear tribe','暗矛巨魔',15737,15761,0),
(8845,530,75,8824,'Darkspear tribe','暗矛巨魔',15737,15761,0),
(8817,68,5,0,'Undercity','幽暗城',15738,15768,1),
(8826,68,75,0,'Undercity','幽暗城',15738,15768,1),
(8832,68,5,8817,'Undercity','幽暗城',15738,15768,0),
(8833,68,75,8826,'Undercity','幽暗城',15738,15768,0),
(8818,81,5,0,'Thunder Bluff','雷霆崖',15739,15767,1),
(8825,81,75,0,'Thunder Bluff','雷霆崖',15739,15767,1),
(8842,81,5,8818,'Thunder Bluff','雷霆崖',15739,15767,0),
(8843,81,75,8825,'Thunder Bluff','雷霆崖',15739,15767,0);

DROP TEMPORARY TABLE IF EXISTS tmp_aq_commendation_check;
CREATE TEMPORARY TABLE tmp_aq_commendation_check AS
SELECT e.entry,
       IF(q.entry IS NOT NULL
          AND q.RewRepFaction1 = e.faction_id
          AND q.RewRepValue1 = e.reward_value
          AND q.PrevQuestId = e.prev_quest
          AND (q.SpecialFlags & 1) = 1
          AND LOCATE(e.faction_en, q.RequestItemsText) > 0
          AND LOCATE(e.faction_zh, l.RequestItemsText_loc4) > 0
          AND (SELECT COUNT(*) FROM creature_questrelation r
               WHERE r.quest=e.entry AND r.id IN
                 (15731,15733,15734,15735,15736,15737,15738,15739,
                  15761,15762,15763,15764,15765,15766,15767,15768))
              = IF(e.is_initial=1,2,1)
          AND (SELECT COUNT(*) FROM creature_involvedrelation r
               WHERE r.quest=e.entry AND r.id IN
                 (15731,15733,15734,15735,15736,15737,15738,15739,
                  15761,15762,15763,15764,15765,15766,15767,15768))
              = IF(e.is_initial=1,2,1)
          AND EXISTS (SELECT 1 FROM creature_questrelation r
                      WHERE r.quest=e.entry AND r.id=e.officer_npc)
          AND EXISTS (SELECT 1 FROM creature_involvedrelation r
                      WHERE r.quest=e.entry AND r.id=e.officer_npc)
          AND (e.is_initial=0 OR EXISTS
              (SELECT 1 FROM creature_questrelation r
               WHERE r.quest=e.entry AND r.id=e.central_npc))
          AND (e.is_initial=0 OR EXISTS
              (SELECT 1 FROM creature_involvedrelation r
               WHERE r.quest=e.entry AND r.id=e.central_npc)),1,0) AS is_correct
FROM tmp_aq_commendation_expected e
LEFT JOIN quest_template q ON q.entry=e.entry
LEFT JOIN locales_quest l ON l.entry=e.entry;

SELECT 'REP_CORRECT', SUM(is_correct) FROM tmp_aq_commendation_check;
SELECT 'REP_WRONG_IDS', COALESCE(GROUP_CONCAT(entry ORDER BY entry),'none')
FROM tmp_aq_commendation_check WHERE is_correct=0;

DROP TEMPORARY TABLE IF EXISTS tmp_aq_supply_expected;
CREATE TEMPORARY TABLE tmp_aq_supply_expected (
    entry MEDIUMINT UNSIGNED NOT NULL PRIMARY KEY,
    npc MEDIUMINT UNSIGNED NOT NULL,
    item_id MEDIUMINT UNSIGNED NOT NULL,
    item_count SMALLINT UNSIGNED NOT NULL,
    reward_item MEDIUMINT UNSIGNED NOT NULL
) ENGINE=MEMORY;

INSERT INTO tmp_aq_supply_expected VALUES
(8846,15701,21436,5,21509),(8847,15701,21436,10,21510),
(8848,15701,21436,15,21511),(8849,15701,21436,20,21512),
(8850,15701,21436,30,21513),(8851,15700,21438,5,21509),
(8852,15700,21438,10,21510),(8853,15700,21438,15,21511),
(8854,15700,21438,20,21512),(8855,15700,21438,30,21513);

SELECT 'SUPPLY_REPEATABLE', COUNT(*)
FROM tmp_aq_supply_expected e
JOIN quest_template q ON q.entry=e.entry
WHERE q.Method=0 AND (q.SpecialFlags & 1)=1
  AND q.ReqItemId1=e.item_id AND q.ReqItemCount1=e.item_count
  AND q.RewItemId1=e.reward_item AND q.RewItemCount1=1;

SELECT 'SUPPLY_DELIVERABLE', COUNT(*)
FROM tmp_aq_supply_expected e
WHERE EXISTS (SELECT 1 FROM creature_questrelation r
              WHERE r.quest=e.entry AND r.id=e.npc)
  AND EXISTS (SELECT 1 FROM creature_involvedrelation r
              WHERE r.quest=e.entry AND r.id=e.npc)
  AND (SELECT COUNT(*) FROM creature_questrelation r
       WHERE r.quest=e.entry AND r.id IN (15700,15701))=1
  AND (SELECT COUNT(*) FROM creature_involvedrelation r
       WHERE r.quest=e.entry AND r.id IN (15700,15701))=1;

SELECT 'SUPPLY_WRONG_IDS', COALESCE(GROUP_CONCAT(e.entry ORDER BY e.entry),'none')
FROM tmp_aq_supply_expected e
LEFT JOIN quest_template q ON q.entry=e.entry
WHERE q.entry IS NULL OR q.Method<>0 OR (q.SpecialFlags & 1)<>1
   OR q.ReqItemId1<>e.item_id OR q.ReqItemCount1<>e.item_count
   OR q.RewItemId1<>e.reward_item OR q.RewItemCount1<>1
   OR NOT EXISTS (SELECT 1 FROM creature_questrelation r
                  WHERE r.quest=e.entry AND r.id=e.npc)
   OR NOT EXISTS (SELECT 1 FROM creature_involvedrelation r
                  WHERE r.quest=e.entry AND r.id=e.npc);

DROP TEMPORARY TABLE tmp_aq_supply_expected;
DROP TEMPORARY TABLE tmp_aq_commendation_check;
DROP TEMPORARY TABLE tmp_aq_commendation_expected;
