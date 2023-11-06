(in-package #:org.shirakumo.fraf.trial.examples)

(defclass raycast-player (transformed-entity listener)
  ((hit :initform (make-hit) :accessor hit)))

(define-handler (raycast-player tick :after) (dt)
  (let ((spd (* 3.0 dt)))
    (cond ((retained :shift)
           (when (retained :a)
             (nq* (orientation raycast-player) (qfrom-angle +vy3+ (+ spd))))
           (when (retained :d)
             (nq* (orientation raycast-player) (qfrom-angle +vy3+ (- spd))))
           (when (retained :w)
             (nq* (orientation raycast-player) (qfrom-angle +vx3+ (+ spd))))
           (when (retained :s)
             (nq* (orientation raycast-player) (qfrom-angle +vx3+ (- spd))))
           (when (retained :c)
             (nq* (orientation raycast-player) (qfrom-angle +vz3+ (+ spd))))
           (when (retained :space)
             (nq* (orientation raycast-player) (qfrom-angle +vz3+ (- spd)))))
          (T
           (when (retained :a)
             (incf (vx (location raycast-player)) (- spd)))
           (when (retained :d)
             (incf (vx (location raycast-player)) (+ spd)))
           (when (retained :w)
             (incf (vz (location raycast-player)) (- spd)))
           (when (retained :s)
             (incf (vz (location raycast-player)) (+ spd)))
           (when (retained :c)
             (incf (vy (location raycast-player)) (- spd)))
           (when (retained :space)
             (incf (vy (location raycast-player)) (+ spd)))))
    (debug-clear)
    (let* ((ray (ray (location raycast-player)
                     (q* (orientation raycast-player) +vx3+)))
           (hit (detect-hit ray (node :a (container raycast-player)) (hit raycast-player))))
      (cond (hit
             (debug-line (ray-location ray) (hit-location hit) :color (vec 1 1 1 1))
             (debug-line (hit-location hit) (v+* (hit-location hit) (ray-direction ray) 100) :color (vec 1 0 0 1))
             (debug-line (hit-location hit) (v+* (hit-location hit) (hit-normal hit) -2)
                         :color-a #.(vec 0 0 0) :color-b #.(vec 0 1 0)))
            (T
             (debug-line (ray-location ray) (v+* (ray-location ray) (ray-direction ray) 100) :color (vec 0 1 0 1)))))))

(defmethod reset ((player raycast-player))
  (vsetf (location player) 0 0 2.5)
  (qsetf (orientation player) 0 0 0 1))

(define-example raycast
  :title "Raycasting"
  (enter (make-instance 'display-controller) scene)
  (enter (make-instance 'vertex-entity :vertex-array (// 'trial 'grid)) scene)
  (enter (make-instance 'collision-body :name :a :primitive (make-sphere)) scene)
  (enter (make-instance 'raycast-player :name :b :location (vec 0 0 +2.5)) scene)
  (enter (make-instance 'target-camera :location (vec3 0.0 8 9) :target (vec 0 0 0) :fov 50) scene)
  (observe! (hit-location (hit (node :b scene))) :title "Location")
  (observe! (hit-normal (hit (node :b scene))) :title "Normal")
  (enter (make-instance 'render-pass) scene))

(defmethod setup-ui ((scene raycast-scene) panel)
  (let ((layout (make-instance 'alloy:grid-layout :col-sizes '(T 120 200) :row-sizes '(30)))
        (focus (make-instance 'alloy:vertical-focus-list)))
    (flet ((shapes ()
             (list (make-sphere)
                   (make-box)
                   (make-cylinder)
                   (make-pill)
                   (make-plane)
                   (make-half-space)
                   (make-triangle)
                   (coerce-object (make-sphere) 'convex-mesh))))
      (alloy:enter "Shape" layout :row 0 :col 1)
      (alloy:represent (physics-primitive (node :a scene)) 'alloy:combo-set
                       :value-set (shapes) :layout-parent layout :focus-parent focus)
      (alloy:enter "Location" layout :row 1 :col 1)
      (alloy:represent (location (node :a scene)) T
                       :layout-parent layout :focus-parent focus)
      (alloy:enter "Orientation" layout :row 2 :col 1)
      (alloy:represent (orientation (node :a scene)) T
                       :layout-parent layout :focus-parent focus)
      (alloy:enter "Reset Ray" layout :row 3 :col 1)
      (make-instance 'alloy:button* :value "..." :on-activate (lambda () (reset (node :b scene)))
                                    :layout-parent layout :focus-parent focus)
      (alloy:finish-structure panel layout focus))))
