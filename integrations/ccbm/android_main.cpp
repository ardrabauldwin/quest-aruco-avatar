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
    char *filter_args[] = {name, load, argv[2], nullptr};
    return naret_ccbm_original_main(3, filter_args);
}
