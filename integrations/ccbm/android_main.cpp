// Adapter around upstream CCBM main. The filter, generated model and
// observation probabilities remain upstream/native; no substitute inference.
#include <fstream>
#include <iostream>
#include <string>
#include <unistd.h>

extern int naret_ccbm_original_main(int, char **);

int main(int argc, char **argv) {
    if (argc != 3) return 64;
    // Each request has a fresh process: upstream global state cannot leak
    // between exercises. Bound faulty/native jobs independently of Godot.
    alarm(8);
    std::ifstream input(argv[1]);
    if (!input) return 66;
    std::ios::sync_with_stdio(false);
    std::cin.rdbuf(input.rdbuf());
    char name[] = "naret-ccbm";
    char load[] = "-l";
    char revisiting[] = "-v";
    char neutral[] = "1";
    // CPR/AED deliberately returns to earlier symbolic states. The upstream
    // default forbids revisiting them, which otherwise kills a second cycle.
    // Factor 1 is neutral: it permits loops without rewarding their repetition.
    char *filter_args[] = {name, revisiting, neutral, load, argv[2], nullptr};
    return naret_ccbm_original_main(5, filter_args);
}
