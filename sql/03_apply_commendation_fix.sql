-- CMaNGOS Classic / classicmangos
-- AQ commendation reputation and war-supplies quest repair.
-- Run only while mangosd is stopped. Safe to run more than once.

USE classicmangos;
SET NAMES utf8;

-- Persistent first-run backup for the standalone SQL rollback script.
CREATE TABLE IF NOT EXISTS aq_backup_20260812_quest_template LIKE quest_template;
INSERT IGNORE INTO aq_backup_20260812_quest_template
SELECT * FROM quest_template
WHERE entry IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);

CREATE TABLE IF NOT EXISTS aq_backup_20260812_locales_quest LIKE locales_quest;
INSERT IGNORE INTO aq_backup_20260812_locales_quest
SELECT * FROM locales_quest
WHERE entry IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);

CREATE TABLE IF NOT EXISTS aq_backup_20260812_creature_questrelation
LIKE creature_questrelation;
INSERT IGNORE INTO aq_backup_20260812_creature_questrelation
SELECT * FROM creature_questrelation
WHERE quest IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);

CREATE TABLE IF NOT EXISTS aq_backup_20260812_creature_involvedrelation
LIKE creature_involvedrelation;
INSERT IGNORE INTO aq_backup_20260812_creature_involvedrelation
SELECT * FROM creature_involvedrelation
WHERE quest IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);

DROP TEMPORARY TABLE IF EXISTS tmp_aq_commendation_expected;
CREATE TEMPORARY TABLE tmp_aq_commendation_expected (
    entry MEDIUMINT UNSIGNED NOT NULL PRIMARY KEY,
    faction_id SMALLINT UNSIGNED NOT NULL,
    reward_value MEDIUMINT NOT NULL,
    prev_quest MEDIUMINT NOT NULL,
    faction_en VARCHAR(64) NOT NULL,
    faction_zh VARCHAR(64) NOT NULL,
    is_ten TINYINT UNSIGNED NOT NULL
) ENGINE=MEMORY DEFAULT CHARSET=utf8;

INSERT INTO tmp_aq_commendation_expected VALUES
(8811,69,5,0,'Darnassus','达纳苏斯',0),
(8819,69,75,0,'Darnassus','达纳苏斯',1),
(8830,69,5,8811,'Darnassus','达纳苏斯',0),
(8831,69,75,8819,'Darnassus','达纳苏斯',1),
(8812,54,5,0,'Gnomeregan Exiles','诺莫瑞根流亡者',0),
(8820,54,75,0,'Gnomeregan Exiles','诺莫瑞根流亡者',1),
(8838,54,5,8812,'Gnomeregan Exiles','诺莫瑞根流亡者',0),
(8839,54,75,8820,'Gnomeregan Exiles','诺莫瑞根流亡者',1),
(8813,47,5,0,'Ironforge','铁炉堡',0),
(8821,47,75,0,'Ironforge','铁炉堡',1),
(8834,47,5,8813,'Ironforge','铁炉堡',0),
(8835,47,75,8821,'Ironforge','铁炉堡',1),
(8814,72,5,0,'Stormwind','暴风城',0),
(8822,72,75,0,'Stormwind','暴风城',1),
(8836,72,5,8814,'Stormwind','暴风城',0),
(8837,72,75,8822,'Stormwind','暴风城',1),
(8815,76,5,0,'Orgrimmar','奥格瑞玛',0),
(8823,76,75,0,'Orgrimmar','奥格瑞玛',1),
(8840,76,5,8815,'Orgrimmar','奥格瑞玛',0),
(8841,76,75,8823,'Orgrimmar','奥格瑞玛',1),
(8816,530,5,0,'Darkspear tribe','暗矛巨魔',0),
(8824,530,75,0,'Darkspear tribe','暗矛巨魔',1),
(8844,530,5,8816,'Darkspear tribe','暗矛巨魔',0),
(8845,530,75,8824,'Darkspear tribe','暗矛巨魔',1),
(8817,68,5,0,'Undercity','幽暗城',0),
(8826,68,75,0,'Undercity','幽暗城',1),
(8832,68,5,8817,'Undercity','幽暗城',0),
(8833,68,75,8826,'Undercity','幽暗城',1),
(8818,81,5,0,'Thunder Bluff','雷霆崖',0),
(8825,81,75,0,'Thunder Bluff','雷霆崖',1),
(8842,81,5,8818,'Thunder Bluff','雷霆崖',0),
(8843,81,75,8825,'Thunder Bluff','雷霆崖',1);

UPDATE quest_template q
JOIN tmp_aq_commendation_expected e ON e.entry = q.entry
SET q.RewRepFaction1 = e.faction_id,
    q.RewRepValue1 = e.reward_value,
    q.PrevQuestId = e.prev_quest,
    q.SpecialFlags = q.SpecialFlags | 1,
    q.RequestItemsText = IF(
        e.is_ten = 0,
        CONCAT('For those adventurers who have but a single commendation signet, I''ll exchange it for a small amount of recognition with ', e.faction_en, '.$B$BPlease bear in mind that it is better to hand over a stack of ten signets at once; your efforts will receive greater recognition in doing so. We offer a single signet exchange as a service for those who don''t have enough for a full stack of ten.$B$BWith that being said, I stand ready to assist you if you still wish to hand in a single signet.'),
        CONCAT('I accept commendation signets from adventurers who have received them in the line of duty. For each set of ten that you hand to me, I''ll make sure that you receive a significant acknowledgement of your deeds with ', e.faction_en, '. I also accept single tokens, but at a much reduced rate of recognition. We are much more interested in greater feats of duty, though no feat will be ignored.$B$BWith that said, I''ll gladly take your signets if you are ready to hand in a set.')
    );

UPDATE locales_quest l
JOIN tmp_aq_commendation_expected e ON e.entry = l.entry
SET l.RequestItemsText_loc4 = IF(
        e.is_ten = 0,
        CONCAT('如果你只有一枚荣誉徽章，我可以用它来帮助你提高在', e.faction_zh, '的知名度。$B$B请注意，你最好一次交给我十枚荣誉徽章，这样你的知名度会获得更大的提高。我们提供针对一枚荣誉徽章的交换服务，是为了方便那些没有足够荣誉徽章凑齐十枚的冒险者。$B$B如果你仍然希望交出一枚徽章，我随时可以为你服务。'),
        CONCAT('完成任务并获得荣誉徽章的冒险者可以把徽章交给我。每次交给我十枚徽章，我都可以显著提升你在', e.faction_zh, '的声望。我也接受单枚徽章，但声望提升会少得多。$B$B如果你准备好了，我可以接受这十枚徽章。')
    );

-- Remove only relations owned by this repair, then recreate the canonical map.
DELETE FROM creature_questrelation
WHERE quest IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845)
  AND id IN (15731,15733,15734,15735,15736,15737,15738,15739,
             15761,15762,15763,15764,15765,15766,15767,15768);

DELETE FROM creature_involvedrelation
WHERE quest IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845)
  AND id IN (15731,15733,15734,15735,15736,15737,15738,15739,
             15761,15762,15763,15764,15765,15766,15767,15768);

INSERT INTO creature_questrelation (id, quest) VALUES
(15731,8811),(15731,8819),(15733,8812),(15733,8820),
(15734,8813),(15734,8821),(15735,8814),(15735,8822),
(15736,8815),(15736,8823),(15737,8816),(15737,8824),
(15738,8817),(15738,8826),(15739,8818),(15739,8825),
(15762,8811),(15762,8819),(15762,8830),(15762,8831),
(15763,8812),(15763,8820),(15763,8838),(15763,8839),
(15764,8813),(15764,8821),(15764,8834),(15764,8835),
(15766,8814),(15766,8822),(15766,8836),(15766,8837),
(15765,8815),(15765,8823),(15765,8840),(15765,8841),
(15761,8816),(15761,8824),(15761,8844),(15761,8845),
(15768,8817),(15768,8826),(15768,8832),(15768,8833),
(15767,8818),(15767,8825),(15767,8842),(15767,8843);

INSERT INTO creature_involvedrelation (id, quest)
SELECT id, quest FROM creature_questrelation
WHERE quest IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845)
  AND id IN (15731,15733,15734,15735,15736,15737,15738,15739,
             15761,15762,15763,15764,15765,15766,15767,15768);

-- Field Marshal Snowfall and Warlord Gorchuk supply-box exchanges.
UPDATE quest_template
SET SpecialFlags = SpecialFlags | 1
WHERE entry BETWEEN 8846 AND 8855;

DELETE FROM creature_questrelation
WHERE quest BETWEEN 8846 AND 8855 AND id IN (15700,15701);
DELETE FROM creature_involvedrelation
WHERE quest BETWEEN 8846 AND 8855 AND id IN (15700,15701);

INSERT INTO creature_questrelation (id, quest) VALUES
(15701,8846),(15701,8847),(15701,8848),(15701,8849),(15701,8850),
(15700,8851),(15700,8852),(15700,8853),(15700,8854),(15700,8855);

INSERT INTO creature_involvedrelation (id, quest) VALUES
(15701,8846),(15701,8847),(15701,8848),(15701,8849),(15701,8850),
(15700,8851),(15700,8852),(15700,8853),(15700,8854),(15700,8855);

DROP TEMPORARY TABLE tmp_aq_commendation_expected;
