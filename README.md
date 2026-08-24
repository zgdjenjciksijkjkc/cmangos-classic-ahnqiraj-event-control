# CMaNGOS Classic Ahn'Qiraj Event Restoration

[简体中文](README.zh-CN.md)

A Windows restoration and control package for the existing Ahn'Qiraj War
Effort content in [CMaNGOS Classic](https://github.com/cmangos/mangos-classic).
It combines the tested event 120–123 phase controller with the completed
commendation/reputation and war-supplies quest repairs.

> This release does **not** repair or recreate the Ahn'Qiraj opening quest
> chain. It does not modify quest 8743 or build the Scepter of the Shifting
> Sands chain. That work is reserved for a future update.

## Included fixes

### Events 120–123 and the Scarab Wall

| Menu | Core phase | Event | Gate | Behavior |
|---|---:|---:|---|---|
| Collection | 1 | 120 | Closed | Resets all 30 resource counters |
| Transportation | 2 | 121 | Closed | Preserves counters and remains manually locked |
| Gong ready | 3 | 122 | Closed | Enters the server's existing pre-gong phase |
| Ten-hour war | 4 | 123 | Open | Uses database time + 36,000 seconds |
| Disable | 0 | — | Open | Disables the War Effort core switch |

The controller:

- restores events 120–127 to server-controlled scheduling (`schedule_type = 0`);
- binds the verified closed-wall objects `49390–49392` to events 120–122;
- validates and updates the 35-number `classiccharacters.world_state.Id = 1` row;
- clears stale persisted AQ event rows before the core selects the new phase;
- sets `WarEffort.Enable = 1` and restores `WarEffort.Rates = 1` for enabled phases;
- uses the existing event-123 army and resonating-crystal data without duplicating it;
- creates database and byte-preserving configuration backups before changes.

`WarEffort.Rates = 1` restores the CMaNGOS base material targets. It does not
force every material to exactly 5,000; the original per-material targets are
not all identical.

### Commendation reputation quests

The package repairs 32 repeatable city-reputation exchanges: quests
`8811–8826` and `8830–8845`.

| Reputation | Faction ID | First 1/10 | Repeat 1/10 | War Effort officer | City officer |
|---|---:|---:|---:|---:|---:|
| Darnassus | 69 | 8811 / 8819 | 8830 / 8831 | 15731 | 15762 |
| Gnomeregan Exiles | 54 | 8812 / 8820 | 8838 / 8839 | 15733 | 15763 |
| Ironforge | 47 | 8813 / 8821 | 8834 / 8835 | 15734 | 15764 |
| Stormwind | 72 | 8814 / 8822 | 8836 / 8837 | 15735 | 15766 |
| Orgrimmar | 76 | 8815 / 8823 | 8840 / 8841 | 15736 | 15765 |
| Darkspear Trolls | 530 | 8816 / 8824 | 8844 / 8845 | 15737 | 15761 |
| Undercity | 68 | 8817 / 8826 | 8832 / 8833 | 15738 | 15768 |
| Thunder Bluff | 81 | 8818 / 8825 | 8842 / 8843 | 15739 | 15767 |

- One commendation awards 5 reputation.
- Ten commendations award 75 reputation.
- Incorrect cross-city mappings and prerequisite links are replaced.
- The matching War Effort officer can complete the first exchanges in place.
- The eight city officers provide the correct repeatable exchanges.
- English and `loc4` Simplified Chinese request text is corrected.

### War-supplies box exchanges

- Alliance quests `8846–8850` are restored on Field Marshal Snowfall (`15701`).
- Horde quests `8851–8855` are restored on Warlord Gorchuk (`15700`).
- All ten exchanges are repeatable and have both start and completion relations.
- Existing medal costs and reward crates `21509–21513` are preserved.

### Windows/MySQL encoding reliability

The controller sends Chinese SQL to `mysql.exe` through a one-use UTF-8 file
instead of the Windows console code page. This fixes the observed `ERROR 1366`
failure without requiring PowerShell 7 or changing `mangosd.exe`.

## Not included yet

- No repair or recreation of the full Ahn'Qiraj opening/Scepter quest chain.
- No write to quest 8743. Its status and broadcasts 11427/11432 are read-only checks.
- No guarantee that every CMaNGOS fork automatically advances 122 → 123 after gong completion.
- No Saurfang march/speech restoration, custom cinematic, or original gate animation/audio patch.
- No executable, core binary patch, client data, database dump, or credentials.

The tested Larmer build already advanced from 122 to 123 after quest 8743, but
that is existing build behavior—not a quest-chain repair supplied here. Menu
option 4 can enter event 123 directly while `mangosd` is stopped. Files under
`source/` are disabled historical research notes and are not installed,
compiled, or required at runtime.

## Compatibility

This release targets Windows CMaNGOS Classic / WoW 1.12.x installations with:

- databases named `classicmangos` and `classiccharacters`;
- `mangosd.conf` in the server root;
- bundled `mysql5\bin\mysql.exe`, `mysqldump.exe`, and `mysqld.exe`;
- AQ events 120–123 and gate objects/templates already present;
- a 35-number AQ state row at `classiccharacters.world_state.Id = 1`;
- the expected CMaNGOS Classic quest and relation table layouts.

Repacked servers can change schemas, GUIDs, and core behavior. The script
validates required tables, columns, rows, and counts before applying the quest
repair and stops on a mismatch.

## Installation

1. Back up the world database, character database, server directory, and `mangosd.conf`.
2. Copy the complete release into the server root. Do not omit the `sql` directory.
3. Stop `mangosd` normally. MySQL may remain running.
4. Run `AQ事件控制.bat` and select an enabled phase (1–4).
5. Start `mangosd`, run `event list`, and use menu 5 for the database status report.

Options 1–4 install the commendation repair idempotently before changing the
phase. Option 6 disables AQ events but deliberately leaves the content repair
installed. Standalone SQL is also available:

- `sql/01_apply_world_data.sql`: static AQ event/gate data;
- `sql/02_rollback_world_data.sql`: static AQ event/gate rollback;
- `sql/03_apply_commendation_fix.sql`: commendation and box exchanges;
- `sql/04_verify_commendation_fix.sql`: read-only verification;
- `sql/05_rollback_commendation_fix.sql`: first-install content rollback.

## Backups and verification

Automatic backups are written under `autobak\AQ事件控制` before each phase or
content change. The status page expects:

- `32/32` correct reputation quests;
- `10/10` repeatable and `10/10` completable supply-box quests;
- `35/35` WorldState fields;
- gate objects bound to `120,121,122`;
- event 123 active and the wall passable when phase 4 is selected.

The relevant tables are MyISAM in the tested database, so the controller makes
an exact `AQ_commendation_rollback_*.sql` backup before applying content changes
and automatically restores it if post-validation fails.

## Project status

This is a community compatibility project and will continue to evolve. It is
not an official CMaNGOS component and is not affiliated with Blizzard
Entertainment. General server documentation is available from the
[CMaNGOS issues/wiki](https://github.com/cmangos/issues/wiki).

Licensed under GPL-2.0. See [LICENSE](LICENSE).
