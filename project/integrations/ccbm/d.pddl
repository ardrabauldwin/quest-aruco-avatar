(define (domain naret-witness)
  (:predicates (assessing) (unresponsive) (called) (breathing-checked)
               (compressing) (compression-only) (finished))
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
    :precondition (and (breathing-checked) (not (compressing))) :effect (compressing)
    :observation (seeCompression 0))
  (:action compression_only
    :precondition (and (breathing-checked) (not (compression-only)) (not (finished)))
    :effect (compression-only) :observation (seeMode 0))
  (:action ventilation
    :precondition (and (compressing) (< (reported-breaths) 256) (not (compression-only)) (not (finished)))
    :effect (increase (reported-breaths) 1) :observation (seeVentilation 0))
  (:action handover
    :precondition (and (compressing) (not (finished))) :effect (finished)
    :observation (seeHandover 0))
)
