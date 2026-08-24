/*
 * ARCHIVED OPTIONAL RESEARCH ONLY -- NOT REQUIRED AND NOT DEPLOYED.
 *
 * In-game testing proved that the target Larmer Build already opens the gate
 * and starts event 123. Its event-123 timer is a Unix expiry timestamp, and
 * world_state field 35 did not change when the gate opened. The assumptions
 * below are therefore unverified for this build. The whole draft is disabled
 * to prevent accidental compilation or deployment.
 */

#if 0

namespace
{
    uint32 const AQ_GATE_TRANSITION_MS = 10 * IN_MILLISECONDS;
    uint32 const BROADCAST_AQ_GONG = 11427;
    uint32 const BROADCAST_AQ_CRYSTALS = 11432;
    uint32 const QUEST_BANG_A_GONG = 8743;
}

/* WorldState method: the only entry point that starts the transition. */
bool WorldState::BeginWarEffortGongTransition(Player* player)
{
    if (m_aqData.m_phase != PHASE_3_GONG_TIME ||
        m_aqData.m_timer != 0 ||
        m_aqData.m_gatesOpen)
        return false;

    // Persist first. A crash must never permit a second first gong.
    m_aqData.m_gatesOpen = true;
    m_aqData.m_timer = AQ_GATE_TRANSITION_MS;
    Save(SAVE_ID_AHN_QIRAJ);

    // Replace this call with the matching Larmer broadcast_text world API.
    SendWarEffortWorldBroadcast(BROADCAST_AQ_GONG, player);

    // This must set all three verified spawns to the native active/open state:
    // 49390 (runes), 49391 (roots), 49392 (main door).
    HandleWarEffortGateSwitch(true);
    return true;
}

/* Existing GameObject quest reward handler. */
bool QuestRewarded_war_effort(Player* player, GameObject* /*go*/,
    Quest const* quest)
{
    if (quest->GetQuestId() == QUEST_BANG_A_GONG)
        sWorldState.BeginWarEffortGongTransition(player);

    // Quest rewards in phase 4 remain valid, but Begin... returns false and
    // therefore cannot replay the broadcast, animation, or timer.
    return true;
}

/* Integrate into the existing WorldState::Update timer-expiry branch. */
void WorldState::FinishExpiredWarEffortPhase()
{
    uint32 const oldPhase = m_aqData.m_phase;
    HandleWarEffortPhaseTransition(oldPhase + 1);

    if (oldPhase == PHASE_3_GONG_TIME &&
        m_aqData.m_phase == PHASE_4_10_HOUR_WAR)
    {
        // Send only after StartWarEffortEvent() has activated event 123.
        SendWarEffortWorldBroadcast(BROADCAST_AQ_CRYSTALS, nullptr);
    }
}

/* Integrate into the exact hook that runs whenever an AQ gate GO is loaded. */
void WorldState::ApplyWarEffortGateStateOnGameObjectLoad(GameObject* go)
{
    switch (go->GetEntry())
    {
        case GO_AQ_GATE_MAIN:
        case GO_AQ_GATE_ROOTS:
        case GO_AQ_GATE_RUNES:
            go->SetGoState(m_aqData.m_gatesOpen ?
                GO_STATE_ACTIVE : GO_STATE_READY);
            break;
        default:
            break;
    }
}

#endif // archived unverified draft
