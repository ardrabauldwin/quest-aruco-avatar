# Current placement: HOLD uses OR —9November2026

## Current decision after initial placement

- Distance<=15cm OR heading difference<=15degrees: hold unconfirmed changes; use Reposition for a deliberate update.
- Distance>15cm AND heading difference>15degrees: eligible for automatic checkpoint confirmation, only with a settled head, all required marker evidence and no hands covering the chest.
- Translation-only movement and rotation-only movement therefore remain held, even if the changing component exceeds15. This is the requested policy.
- A move already confirmed continues toward its fixed destination; entering the15cm/15degree region during that accepted approach does not cancel it. Head movement or missing evidence still holds/cancels automatic following.

Initial placement and Reposition retain startup30/33… comparisons, earliest42stable readings,100reading startup fallback. Automatic confirmations use30/33… with four1.5mm/1degree comparisons and newest3 agreeing, no forced100fallback. After floor locking, robust position is coordinate mediansXYZ and orientation is a circular yaw-only medoid. Full3D support remains for nonfloorlocked standalone callers.

Movement settings remain2cm/.3degree dead zones,1.2s smoothing,2s rest pull,1mm/.1degree landing margins. Rest equals the confirmed destination; no additional fiveposemedoid,5cmraw continuation allowance or8cm/8degree endpoint reanchor.

The head-motion gate uses0.3s history,>0.15m/s OR>20degrees/s full rotation, and0.5s settling. No foot-end region or1.8m range gate is active. Reposition is on the left-hand menu belowStart/Save; it preserves saved alignment,floor/chest measurements andtrainingprogress.

The PPT is deliberately not edited at the user's request. No APK built or installed. The15cm/15degree policy is experimental, not proof of measurement accuracy.
