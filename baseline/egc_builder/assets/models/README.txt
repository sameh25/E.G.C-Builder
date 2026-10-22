Optional licensed models (not bundled).
Put a SketchUp file named appliance_<kind>.skp here (kinds: oven, microwave, hob_electric, hob_gas, hood_slim,
hood_chimney, fridge, freezer, dishwasher, washer, coffee, warming_drawer, wine_cooler, sink).
Axes: x = width, y = depth (front faces -y), z = height. Use only models you own or that are licensed for commercial redistribution.

E.G.C NEVER DISTORTS a model. Order of choice for the appliance slot:
  1. the model at its exact native size (2 mm tolerance)
  2. a size variant listed in the sidecar (appliance_<kind>.json "variants") that matches the slot
  3. uniform scaling (ONE factor on x, y, z - proportions never change) ONLY if the sidecar allows it:
       "uniform_scale": {"min": 0.98, "max": 1.02}
     and the three slot/native ratios agree within 0.5 %
  4. otherwise the model is rejected (reason written to %APPDATA%\EGC_Builder\diagnostics.log) and the generated
     E.G.C appliance is built instead.
A 600 mm model is never turned into a 450 mm one; supply a 450 mm variant instead.
Per-axis scaling ("scale_axes") is not supported: it is ignored and logged.

Sidecar (optional) appliance_<kind>.json:
  { "native": {"w":595,"d":550,"h":595},
    "uniform_scale": {"min":0.98,"max":1.02},
    "fit": {"min_w":560,"max_w":600},
    "variants": [{"file":"appliance_oven_45.skp","w":450,"d":550,"h":595}] }
