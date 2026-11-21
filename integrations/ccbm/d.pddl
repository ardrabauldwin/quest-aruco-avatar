(define (domain naret-witness)
  (:predicates (assessing) (unresponsive) (called) (breathing-checked)
               (compressing) (compression-only) (finished)
               (aed-requested) (aed-attached) (aed-paused) (analysis-cleared)
               (analyzed) (shock-needed) (no-shock) (shock-cleared))
  (:functions (reported-breaths) - (number 0 256))
  (:action begin_check
    :precondition (not (assessing)) :effect (assessing)
    :observation (seeBegin 0))
  (:action check_responsiveness
    :precondition (and (assessing) (not (unresponsive))) :effect (unresponsive)
    :observation (seeResponse 0))
  (:action call_emergency
    :precondition (and (unresponsive) (not (called))) :effect (called)
    :observation (seeCall 0))
  (:action check_breathing
    :precondition (and (called) (not (breathing-checked))) :effect (breathing-checked)
    :observation (seeBreathing 0))
  (:action compression
    :precondition (and (breathing-checked) (not (compressing)) (not (aed-paused)) (not (finished))) :effect (compressing)
    :observation (seeCompression 0))
  (:action compression_only
    :precondition (and (breathing-checked) (not (compression-only)) (not (finished)))
    :effect (compression-only) :observation (seeMode 0))
  (:action ventilation
    :precondition (and (compressing) (< (reported-breaths) 256) (not (compression-only)) (not (aed-paused)) (not (finished)))
    :effect (increase (reported-breaths) 1) :observation (seeVentilation 0))
  (:action handover
    :precondition (and (breathing-checked) (not (finished))) :effect (finished)
    :observation (seeHandover 0))

  (:action request_aed
    :precondition (and (unresponsive) (not (aed-requested)) (not (finished)))
    :effect (aed-requested) :observation (seeRequestAED 0))
  (:action attach_aed
    :precondition (and (breathing-checked) (not (aed-attached)) (not (finished)))
    :effect (and (aed-attached) (aed-paused) (not (compressing))) :observation (seeAttachAED 0))
  (:action clear_for_analysis
    :precondition (and (aed-paused) (aed-attached) (not (analysis-cleared)) (not (analyzed)) (not (finished)))
    :effect (analysis-cleared) :observation (seeClear 0))
  (:action analyze_rhythm
    :precondition (and (aed-paused) (analysis-cleared) (not (analyzed)) (not (finished)))
    :effect (analyzed) :observation (seeAnalyze 0))
  (:action shock_advised
    :precondition (and (analyzed) (not (shock-needed)) (not (no-shock)) (not (finished)))
    :effect (shock-needed) :observation (seeShockAdvised 0))
  (:action no_shock_advised
    :precondition (and (analyzed) (not (shock-needed)) (not (no-shock)) (not (finished)))
    :effect (no-shock) :observation (seeNoShock 0))
  (:action clear_for_shock
    :precondition (and (aed-paused) (shock-needed) (not (shock-cleared)) (not (finished)))
    :effect (shock-cleared) :observation (seeClear 0))
  (:action shock
    :precondition (and (aed-paused) (shock-needed) (shock-cleared) (not (finished)))
    :effect (and (not (aed-paused)) (not (compressing)) (not (analysis-cleared)) (not (analyzed)) (not (shock-needed)) (not (no-shock)) (not (shock-cleared))) :observation (seeShock 0))
  (:action resume_cpr
    :precondition (and (aed-paused) (no-shock) (not (finished)))
    :effect (and (not (aed-paused)) (not (compressing)) (not (analysis-cleared)) (not (analyzed)) (not (shock-needed)) (not (no-shock)) (not (shock-cleared))) :observation (seeResume 0))
  (:action reassess
    :precondition (and (aed-attached) (not (aed-paused)) (not (finished)))
    :effect (and (aed-paused) (not (compressing)) (not (analysis-cleared)) (not (analyzed)) (not (shock-needed)) (not (no-shock)) (not (shock-cleared))) :observation (seeReassess 0))
  (:action patient_contact
    :precondition (and (aed-paused) (aed-attached) (or (analysis-cleared) (analyzed) (shock-needed) (no-shock) (shock-cleared)) (not (finished)))
    :effect (and (not (analysis-cleared)) (not (analyzed)) (not (shock-needed)) (not (no-shock)) (not (shock-cleared))) :observation (seeContact 0))
  (:action recovery
    :precondition (and (aed-paused) (no-shock) (not (finished)))
    :effect (finished) :observation (seeRecovery 0))
)
