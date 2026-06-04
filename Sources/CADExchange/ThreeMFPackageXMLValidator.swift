import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CADCore

enum ThreeMFPackageXMLValidator {
    static func validate(contentTypes: Data, relationships: Data) throws {
        try ThreeMFContentTypesXMLReader.validate(contentTypes)
        try ThreeMFRelationshipsXMLReader.validate(relationships)
    }
}

private final class ThreeMFContentTypesXMLReader: NSObject, XMLParserDelegate {
    private var importError: ImportError?
    private var elementStack: [String] = []
    private var defaults: [String: String] = [:]

    static func validate(_ data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw ImportError.invalidData("3MF content types XML is not UTF-8.")
        }
        let reader = ThreeMFContentTypesXMLReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else {
            if let importError = reader.importError {
                throw importError
            }
            throw ImportError.invalidData(parser.parserError?.localizedDescription ?? "Invalid 3MF content types XML.")
        }
        try reader.validateResolvedDefaults()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        guard namespaceURI == packageContentTypesNamespaceURI else {
            fail("3MF content types element \(name) must use the OPC content-types namespace.", parser: parser)
            return
        }
        if elementStack.isEmpty {
            guard name == "Types" else {
                fail("3MF content types root element must be Types.", parser: parser)
                return
            }
            guard attributeDict.isEmpty else {
                fail("3MF content types root contains unsupported attributes.", parser: parser)
                return
            }
        } else {
            guard elementStack == ["Types"], name == "Default" else {
                fail("Unsupported 3MF content types element \(name).", parser: parser)
                return
            }
            readDefault(attributeDict, parser: parser)
            guard importError == nil else {
                return
            }
        }
        elementStack.append(name)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        guard elementStack.last == name else {
            fail("3MF content types XML nesting is inconsistent.", parser: parser)
            return
        }
        elementStack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("3MF content types XML contains unsupported character data.", parser: parser)
            return
        }
    }

    private func readDefault(_ attributes: [String: String], parser: XMLParser) {
        guard Set(attributes.keys) == ["Extension", "ContentType"] else {
            fail("3MF content type Default must contain only Extension and ContentType.", parser: parser)
            return
        }
        guard let rawExtension = attributes["Extension"],
              let contentType = attributes["ContentType"] else {
            fail("3MF content type Default is malformed.", parser: parser)
            return
        }
        let ext = rawExtension.lowercased()
        guard expected3MFContentTypes.keys.contains(ext),
              expected3MFContentTypes[ext] == contentType else {
            fail("Unsupported 3MF content type Default for \(rawExtension).", parser: parser)
            return
        }
        guard defaults[ext] == nil else {
            fail("Duplicate 3MF content type Default for \(rawExtension).", parser: parser)
            return
        }
        defaults[ext] = contentType
    }

    private func validateResolvedDefaults() throws {
        guard defaults == expected3MFContentTypes else {
            throw ImportError.invalidData("3MF content types must declare only the supported rels and model defaults.")
        }
    }

    private func fail(_ message: String, parser: XMLParser) {
        importError = ImportError.invalidData(message)
        parser.abortParsing()
    }
}

private final class ThreeMFRelationshipsXMLReader: NSObject, XMLParserDelegate {
    private var importError: ImportError?
    private var elementStack: [String] = []
    private var modelRelationshipCount = 0

    static func validate(_ data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw ImportError.invalidData("3MF relationships XML is not UTF-8.")
        }
        let reader = ThreeMFRelationshipsXMLReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else {
            if let importError = reader.importError {
                throw importError
            }
            throw ImportError.invalidData(parser.parserError?.localizedDescription ?? "Invalid 3MF relationships XML.")
        }
        guard reader.modelRelationshipCount == 1 else {
            throw ImportError.invalidData("3MF relationships must declare exactly one model relationship.")
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        guard namespaceURI == packageRelationshipsNamespaceURI else {
            fail("3MF relationships element \(name) must use the OPC relationships namespace.", parser: parser)
            return
        }
        if elementStack.isEmpty {
            guard name == "Relationships" else {
                fail("3MF relationships root element must be Relationships.", parser: parser)
                return
            }
            guard attributeDict.isEmpty else {
                fail("3MF relationships root contains unsupported attributes.", parser: parser)
                return
            }
        } else {
            guard elementStack == ["Relationships"], name == "Relationship" else {
                fail("Unsupported 3MF relationships element \(name).", parser: parser)
                return
            }
            readRelationship(attributeDict, parser: parser)
            guard importError == nil else {
                return
            }
        }
        elementStack.append(name)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        guard elementStack.last == name else {
            fail("3MF relationships XML nesting is inconsistent.", parser: parser)
            return
        }
        elementStack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("3MF relationships XML contains unsupported character data.", parser: parser)
            return
        }
    }

    private func readRelationship(_ attributes: [String: String], parser: XMLParser) {
        guard Set(attributes.keys) == ["Target", "Id", "Type"] else {
            fail("3MF relationship must contain only Target, Id, and Type.", parser: parser)
            return
        }
        guard let id = attributes["Id"], !id.isEmpty,
              attributes["Target"] == "/3D/3dmodel.model",
              attributes["Type"] == threeMFModelRelationshipType else {
            fail("3MF relationship does not target the supported model part.", parser: parser)
            return
        }
        guard modelRelationshipCount == 0 else {
            fail("Duplicate 3MF model relationship.", parser: parser)
            return
        }
        modelRelationshipCount += 1
    }

    private func fail(_ message: String, parser: XMLParser) {
        importError = ImportError.invalidData(message)
        parser.abortParsing()
    }
}

private let packageContentTypesNamespaceURI = "http://schemas.openxmlformats.org/package/2006/content-types"
private let packageRelationshipsNamespaceURI = "http://schemas.openxmlformats.org/package/2006/relationships"
private let threeMFModelRelationshipType = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
private let expected3MFContentTypes = [
    "rels": "application/vnd.openxmlformats-package.relationships+xml",
    "model": "application/vnd.ms-package.3dmanufacturing-3dmodel+xml"
]

private func localName(_ value: String) -> String {
    value.split(separator: ":").last.map(String.init) ?? value
}
