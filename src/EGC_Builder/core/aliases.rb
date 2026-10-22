# encoding: UTF-8
# frozen_string_literal: true
#
# Public API aliases.
#
# The engineering modules live under EGC::Ops::* (namespaced by concern), but
# the documented/public surface - and every call-site in the original 1.2x
# codebase plus the released test scripts - uses the short form:
#
#   EGC::Cutlist.invalidate_cache!
#   EGC::CAM.reset_toolpaths!
#   EGC::Nesting.nest(...)
#   EGC::SpaceTool.insert(...)
#
# Rather than duplicate implementations, we bind the short names to the same
# module objects. There is exactly one implementation of each.

module EGC
  Cutlist     = EGC::Ops::Cutlist
  CAM         = EGC::Ops::CAM
  Nesting     = EGC::Ops::Nesting
  SpaceTool   = EGC::Ops::SpaceTool
  ExecWorktop = EGC::Ops::ExecWorktop
  AssistantEdit = EGC::Ops::AssistantEdit
  ProductionSync = EGC::Ops::ProductionSync
  Interference = EGC::Ops::Interference
  Corner      = EGC::Ops::Corner
  Appliances  = EGC::Ops::Appliances
  Snap        = EGC::Ops::Snap
end
