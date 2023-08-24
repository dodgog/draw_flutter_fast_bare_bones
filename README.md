# draw_flutter_fast_bare_bones

## List of ideas

- [x] Implement pressure and see how that works, that's the event object
        ! Slight pressure variation, as acheived with the thinning parameter set to 0.2 seems to look very good
        yet it's unnoticable that the thickness of the strock varies at all.
- [x] Implement different Beziers with more degrees of freedom
        This is in how the path thing works in flutter
        Ideally, however, the current and past stroke drawing would be minimally different to prevent the
        back-propagating jiggle
        ! This didn't change anything, even if we draw the line in linear segments, we see no difference
- [x] Use Saber's ferehand drawing setting
        ! Seems to have caused an improvement. A good amount of precision
- [ ] Remove some points from the raw stroke data to save space (perhaps use distance and curvature as metrics for this filtering)
- [ ] Don't redraw all the curves on the screen every time a new one is added (perhaps by layering an array of canvases?
        that's bad.)
