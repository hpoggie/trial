(in-package #:org.shirakumo.fraf.trial.examples)

(define-example tilemap
  :title "Tile Maps"
  :description "Illustrates how to display a tilemap."
  (enter (make-instance 'tile-layer :tile-data (assets:asset :tilemap) :name :tilemap) scene)
  (enter (make-instance 'sidescroll-camera :zoom 2.0) scene)
  (enter (make-instance 'render-pass) scene))

(define-example isometric-tilemap
  :title "Isometric Tile Maps"
  :description "Illustrates how to display an isometric tilemap."
  (enter (make-instance 'tile-layer :tile-data (assets:asset :isometric-tilemap) :name :tilemap) scene)
  (enter (make-instance 'sidescroll-camera :zoom 2.0) scene)
  (enter (make-instance 'render-pass) scene))
