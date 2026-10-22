# encoding: UTF-8
# frozen_string_literal: true

module EGC
  # Base class for all extension errors.
  class Error < StandardError; end

  # Raised when the frozen dimensional contract is violated.
  class IntegrityError < Error; end

  # Raised when a cabinet cannot be found / is malformed.
  class CabinetError < Error; end

  # Raised when an insertion operation is unsupported for a zone.
  class InsertionError < Error; end

  # Raised when geometry would self-intersect in a forbidden way.
  class GeometryError < Error; end
end
