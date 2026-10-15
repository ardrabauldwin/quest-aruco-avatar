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
Probability post_observe_action(size_t) {
    if (observed.empty()) return 1;
    return predicted == observed ? 0.98 : 0.02;
}
Probability post_observe_state(StatePtr) { return 1; }
