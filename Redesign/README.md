# Redesign

The plan for re-imagining Backdrop's console. Nothing in this folder is built into the app.

- [Spec.md](Spec.md) is the design as agreed: the Booth for show mode, the Studio for edit mode, the rail, the cue gallery, Go To on G, and the timeline. Where it and the mockups disagree, it wins.
- [Plan.md](Plan.md) is how to build it, phase by phase. It names the files each step changes, the model changes, the tests, the debug snapshots that prove each screen, and the safety rules every phase must keep.
- [Images/](Images/) holds a picture of each screen, rendered from the mockups at twice their size and shown in Spec.md beside the sections they illustrate: the Booth, the Studio in light and dark, the rail, the standby card's states, warnings, Beginners and Recovery, the cue gallery, the timeline, editing on the stage, and the smaller pieces.
- [Mockups.html](Mockups.html) is the illustrated proposal the design came from. Open it in a browser. It reflects the agreed changes: square row tabs, B in the key row, On stage before Next, no green lamps but the projector's, and Go To on G.

Backdrop isn't live, so the plan changes the model freely and deletes what it replaces, with no migration and no switches to turn things off.
