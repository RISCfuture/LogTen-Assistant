import CoreData
import Foundation
import LogbookModel

/// The stored, non-transient attribute values of one managed object, by attribute name.
struct ScalarValues {
  private let values: [String: FieldValue]

  /// The values whose names are LogTen field keys of the object's own entity.
  var fieldValues: [LogTenFieldKey: FieldValue] {
    var fields = [LogTenFieldKey: FieldValue]()
    for (name, value) in values {
      if let key = LogTenFieldKey(rawValue: name) { fields[key] = value }
    }
    return fields
  }

  /// The values of custom slots that are set.
  var customValues: [LogTenFieldKey: FieldValue] {
    fieldValues.filter { key, value in key.customSlot != nil && value.isSet }
  }

  /// Every value as JSON, for fingerprinting.
  var json: JSONValue { .object(values.mapValues(\.jsonValue)) }

  init(_ object: NSManagedObject) {
    var values = [String: FieldValue]()
    for (name, attribute) in object.entity.attributesByName where !attribute.isTransient {
      if let value = Self.fieldValue(object.value(forKey: name), type: attribute.type) {
        values[name] = value
      }
    }
    self.values = values
  }

  private static func fieldValue(_ value: Any?, type: NSAttributeDescription.AttributeType)
    -> FieldValue?
  {
    guard let value else { return .null }
    switch type {
      case .integer16, .integer32, .integer64:
        return (value as? NSNumber).map { .integer($0.intValue) }
      case .float:
        return (value as? NSNumber).map { .number(Self.typedDecimal(of: $0)) }
      case .decimal, .double:
        return (value as? NSNumber).map { .number($0.doubleValue) }
      case .boolean:
        return (value as? NSNumber).map { .boolean($0.boolValue) }
      case .string:
        return (value as? String).map(FieldValue.text)
      case .date:
        return (value as? Date).map(FieldValue.date)
      default:
        return nil
    }
  }

  /// The decimal a user would have typed for a stored `Float`, so `1233.4` reads as `1233.4`
  /// instead of `1233.4000244140625`.
  private static func typedDecimal(of number: NSNumber) -> Double {
    let float = number.floatValue
    return Double(float.description) ?? Double(float)
  }

  func text(_ name: String) -> String? { values[name]?.text }

  func integer(_ name: String) -> Int? {
    guard case .integer(let value) = values[name] else { return nil }
    return value
  }

  func number(_ name: String) -> Double? { values[name]?.number }

  func date(_ name: String) -> Date? { values[name]?.date }

  func flag(_ name: String) -> Bool { optionalFlag(name) ?? false }

  func optionalFlag(_ name: String) -> Bool? {
    guard case .boolean(let value) = values[name] else { return nil }
    return value
  }
}
