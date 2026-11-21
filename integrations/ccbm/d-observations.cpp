#include <iostream>
#include <string>
// Interface follows upstream Examples/Shoes/d-observations.cpp.
// Likelihoods are prototype constants, NOT trained sensor accuracies.
static std::string observed;
static std::string predicted;
static bool initialObservation = true;
void seeBegin(int, int) { predicted = "begin_check"; }
void seeResponse(int, int) { predicted = "check_responsiveness"; }
void seeCall(int, int) { predicted = "call_emergency"; }
void seeBreathing(int, int) { predicted = "check_breathing"; }
void seeCompression(int, int) { predicted = "compression"; }
void seeMode(int, int) { predicted = "compression_only"; }
void seeVentilation(int, int) { predicted = "ventilation"; }
void seeHandover(int, int) { predicted = "handover"; }
void specialOpCallback(int, int) {}
bool fetchObservation() {
    if (initialObservation) { initialObservation = false; observed.clear(); return true; }
    return bool(std::cin >> observed);
}
void pre_observe_action(size_t) { predicted.clear(); }
void pre_observe_state(StatePtr) {}
// Accepted simulator events are known structural facts, not noisy speech or
// proof of real clinical technique. The bridge cannot accept these from ASR.
static bool isSoftwareEvent(const std::string &code) {
    return code == "compression" ||
           code == "attach_aed" ||
           code == "analyze_rhythm" ||
           code == "shock_advised" ||
           code == "no_shock_advised" ||
           code == "shock" ||
           code == "resume_cpr" ||
           code == "reassess" ||
           code == "patient_contact" ||
           code == "recovery";
}
Probability post_observe_action(size_t) {
    if (observed.empty()) return 1;
    if (isSoftwareEvent(observed) || isSoftwareEvent(predicted))
        return predicted == observed ? 1 : 0;
    // Existing prototype speech likelihood, with the error mass distributed
    // across the other speech codes. This is not trained recognition accuracy.
    return predicted == observed ? 0.98 : 0.02 / (9 - 1);
}
Probability post_observe_state(StatePtr) { return 1; }
void seeRequestAED(int, int) { predicted = "request_aed"; }
void seeAttachAED(int, int) { predicted = "attach_aed"; }
void seeClear(int, int) { predicted = "clear_patient"; }
void seeAnalyze(int, int) { predicted = "analyze_rhythm"; }
void seeShockAdvised(int, int) { predicted = "shock_advised"; }
void seeNoShock(int, int) { predicted = "no_shock_advised"; }
void seeShock(int, int) { predicted = "shock"; }
void seeResume(int, int) { predicted = "resume_cpr"; }
void seeReassess(int, int) { predicted = "reassess"; }
void seeContact(int, int) { predicted = "patient_contact"; }
void seeRecovery(int, int) { predicted = "recovery"; }
