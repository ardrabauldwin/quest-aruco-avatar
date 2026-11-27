// =============================================================================
//  d-observations.cpp  —  OBSERVATION MODEL of the NaReT CCBM model
// =============================================================================
//
//  WHAT THIS FILE DOES
//  -------------------
//  CCBM needs two kinds of knowledge:
//    1. d.pddl     -> which actions are POSSIBLE in which state (the rules)
//    2. this file  -> how well an action FITS what was OBSERVED
//
//  This file computes the likelihood   p( observation | action ):
//  "If the trainee really did this action, how likely is the observation?"
//
//  HOW IT IS BUILT AND USED
//  ------------------------
//  The CCBM compiler `rc` (RC3) generates C++ code from d.pddl / p.pddl and
//  compiles it TOGETHER with this file into one filter program
//  (build.sh -> out/p-filter on the PC; build_android.py -> library in the Quest
//  app). The function names below are fixed by the CCBM interface (taken from
//  the upstream example Examples/Shoes). CCBM calls them, not our own code.
//  => Changing a number here needs a rebuild of CCBM and of the app.
//
//  WHAT HAPPENS IN ONE STEP
//  ------------------------
//  The app sends ONE word per step (the observation), e.g. "check_breathing".
//  CCBM keeps many guesses (particles) about what the trainee did. Order of
//  calls (checked in the CCBM source: src/main.cpp main loop and
//  Particle::update(), see Man/CCBM_Quickstart_Guide.md):
//
//    for each time step:
//      fetchObservation()          ONCE per step: read the word into `observed`
//      for each particle (guess):
//        pre_observe_action()      clear `predicted`
//        pre_observe_state()       (unused here)
//        doCallbacksAndObservations()
//                                  CCBM calls the :observation clause of this
//                                  particle's action -> seeXxx() sets `predicted`
//        pyx = post_observe_action() * post_observe_state()
//                                  compare `predicted` with `observed`
//        weight = weight * pyx     then the weights are normalised
//
//  WORKED EXAMPLE
//  --------------
//  History so far: begin_check, check_responsiveness, call_emergency.
//  Now the trainee says "He is not breathing normally."
//  -> speech recognition + rules -> the app sends the word  check_breathing
//
//  In this state d.pddl allows e.g. these actions (all others are impossible):
//      check_breathing   (precondition: called, not breathing-checked)  -> possible
//      request_aed       (precondition: unresponsive, not aed-requested) -> possible
//  Assume both are equally likely before listening: 0.5 each.
//
//  CCBM tests guess "check_breathing":
//      seeBreathing()          -> predicted = "check_breathing"
//      post_observe_action()   -> speech, predicted == observed  -> 0.98
//  CCBM tests guess "request_aed":
//      seeRequestAED()         -> predicted = "request_aed"
//      post_observe_action()   -> speech, predicted != observed  -> 0.02/8 = 0.0025
//
//      check_breathing : 0.5 * 0.98   = 0.49
//      request_aed     : 0.5 * 0.0025 = 0.00125
//      normalised      : 0.49 / (0.49 + 0.00125) = 0.997  -> 99.7 %
//
//  ccbm_bridge.gd accepts the step if this posterior >= 0.90 (it is),
//  and the scenario state machine then checks it once more.
//
//  Counter-example: the same word arrives BEFORE the 112 call. Then
//  check_breathing is impossible in d.pddl (precondition "called" is false),
//  so its probability is 0 — however clearly it was heard.
// =============================================================================

#include <iostream>   // std::cin: the observations are read from standard input
#include <string>     // observations and action names are words
// Interface follows upstream Examples/Shoes/d-observations.cpp.
// Likelihoods are prototype constants, NOT trained sensor accuracies.

static std::string observed;          // WHAT CAME IN this step, e.g. "check_breathing"
static std::string predicted;         // WHICH ACTION CCBM IS TESTING (set by seeXxx)
static bool initialObservation = true; // true only before the very first step

// --- "see" callbacks, part 1: BLS steps --------------------------------------
// Each action in d.pddl names one of these in ":observation (seeXxx 0)".
// They only remember which action is being tested. The int arguments are unused.
void seeBegin(int, int) { predicted = "begin_check"; }             // "the scene is safe"
void seeResponse(int, int) { predicted = "check_responsiveness"; } // "he is not responding"
void seeCall(int, int) { predicted = "call_emergency"; }           // 112 called
void seeBreathing(int, int) { predicted = "check_breathing"; }     // "not breathing normally"
void seeCompression(int, int) { predicted = "compression"; }       // compressions started
void seeMode(int, int) { predicted = "compression_only"; }         // no breaths, only compressions
void seeVentilation(int, int) { predicted = "ventilation"; }       // one breath
void seeHandover(int, int) { predicted = "handover"; }             // handover to the crew
void specialOpCallback(int, int) {}                                // required by CCBM, unused

// --- read the next observation ----------------------------------------------
// First call: an EMPTY observation, so the filter starts from p.pddl's initial
// state without evidence. Later calls: one word per step from standard input,
// e.g. the app writes "begin_check", "check_responsiveness", ... line by line.
// Returns false when the input ends -> the filter stops.
bool fetchObservation() {
    if (initialObservation) { initialObservation = false; observed.clear(); return true; }
    return bool(std::cin >> observed);
}

// Clear the previous guess before the next action is tested.
void pre_observe_action(size_t) { predicted.clear(); }
// The same for states: not used in this model.
void pre_observe_state(StatePtr) {}

// --- software events -----------------------------------------------------------
// Two kinds of observations:
//   SPEECH          uncertain (can be misheard), e.g. "check_breathing"
//   SOFTWARE EVENT  certain: produced by the app itself (hand tracking, the
//                   virtual AED, the scenario). Speech can never create them —
//                   saying "I gave a shock" is never accepted as a shock.
// Accepted simulator events are known structural facts, not noisy speech or
// proof of real clinical technique. The bridge cannot accept these from ASR.
static bool isSoftwareEvent(const std::string &code) {
    return code == "compression" ||       // compressions detected by hand tracking
           code == "attach_aed" ||        // both pads on their outlines
           code == "analyze_rhythm" ||    // the AED analysed
           code == "shock_advised" ||     // AED decision: shock
           code == "no_shock_advised" ||  // AED decision: no shock
           code == "shock" ||             // shock button pressed
           code == "resume_cpr" ||        // CPR resumed after "no shock"
           code == "reassess" ||          // 2-minute re-analysis
           code == "patient_contact" ||   // patient touched during the analysis
           code == "recovery";            // circulation back (trainer button)
}

// --- THE CORE: likelihood p(observed | predicted) ---------------------------------
Probability post_observe_action(size_t) {
    // 1) Nothing observed (first step): no evidence, every guess is fine -> 1.
    if (observed.empty()) return 1;
    // 2) A software event is involved: certain, so exact comparison.
    //    match -> 1, otherwise -> 0 (that guess is eliminated).
    //    Example: observed "shock", guess "check_breathing" -> 0.
    if (isSoftwareEvent(observed) || isSoftwareEvent(predicted))
        return predicted == observed ? 1 : 0;
    // 3) Speech: uncertain. The right action gets 0.98; the remaining 0.02 is
    //    shared by the 8 OTHER speech codes (9 speech codes - 1 = 8): 0.0025 each.
    //    The 9 speech codes: begin_check, check_responsiveness, call_emergency,
    //    check_breathing, compression_only, ventilation, handover, request_aed,
    //    clear_patient.
    //    One fixed value for all steps, languages and noise levels; measured
    //    recognition rates per step would be more realistic.
    // Existing prototype speech likelihood, with the error mass distributed
    // across the other speech codes. This is not trained recognition accuracy.
    return predicted == observed ? 0.98 : 0.02 / (9 - 1);
}

// States give no extra evidence in this model -> always 1.
Probability post_observe_state(StatePtr) { return 1; }

// --- "see" callbacks, part 2: AED ---------------------------------------------
void seeRequestAED(int, int) { predicted = "request_aed"; }        // "get the defibrillator" (speech)
void seeAttachAED(int, int) { predicted = "attach_aed"; }          // pads on (software)
void seeClear(int, int) { predicted = "clear_patient"; }           // "stand clear" (speech); used by
                                                                   // clear_for_analysis AND clear_for_shock
void seeAnalyze(int, int) { predicted = "analyze_rhythm"; }        // AED analysis (software)
void seeShockAdvised(int, int) { predicted = "shock_advised"; }    // decision: shock (software)
void seeNoShock(int, int) { predicted = "no_shock_advised"; }      // decision: no shock (software)
void seeShock(int, int) { predicted = "shock"; }                   // shock delivered (software)
void seeResume(int, int) { predicted = "resume_cpr"; }             // CPR resumed (software)
void seeReassess(int, int) { predicted = "reassess"; }             // re-analysis (software)
void seeContact(int, int) { predicted = "patient_contact"; }       // patient touched (software)
void seeRecovery(int, int) { predicted = "recovery"; }             // circulation back (software)
