# Round 83 lane w: Material key_value_editor doubled label

Symptom: the first row's "Name" and "Value of Accept" labels were printed twice (a ghost over the floated label) in Material, MaterialDark, and as a smaller leftover in Neper, NeperDark.

Bisect (render of examples/looks/h_key_value_editor.e at each commit, hash of material/key_value_editor.png): identical to the committed picture at 0fc003f27 and 62cbfeb1c, different from 51c3eb3e0 on. The only library change between them touching fields is 62689b75f (`notched` in control.e): the label is lifted half its height above the box and the cut that hid the edge now starts at the edge, so the half of the label above the edge is no longer filled.

Root cause: `key_value_editor_of` builds the column headings "Name" / "Value" for every look but gives them zero height under the Neper and Material profiles (their fields carry the label in the notch). Zero height does not clip, so the heading text paints over the first row; the old notch fill happened to cover it. Fix (collection.e, one place): for a zero heading height the heading nodes are empty zero-height boxes (same layout, no text). Windows, Linux and Cupertino keep their heading line and are byte identical.

Sheets changed: material, material-dark, neper, neper-dark key_value_editor (1x and 1.5x). It is the only sheet app using the path.

Flutter comparison: none possible; ref/flutter has no key-value editor (composite control). Rows stay review.
