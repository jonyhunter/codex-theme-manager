import CryptoKit
import Foundation

private struct PublicKeyDocument: Decodable {
  let kty: String
  let crv: String
  let x: String
}

private enum SignatureTestError: Error {
  case invalid(String)
}

@main
enum UpdateSignatureTests {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      throw SignatureTestError.invalid("Expected the updates directory.")
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let document = try JSONDecoder().decode(
      PublicKeyDocument.self,
      from: Data(contentsOf: root.appendingPathComponent("public-key.json"))
    )
    guard document.kty == "OKP", document.crv == "Ed25519" else {
      throw SignatureTestError.invalid("Unexpected public-key type.")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: decodeBase64URL(document.x))

    for filename in ["stable.json", "themes.json"] {
      let data = try Data(contentsOf: root.appendingPathComponent(filename))
      let signatureText = try String(
        contentsOf: root.appendingPathComponent("\(filename).sig"),
        encoding: .utf8
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      guard let signature = Data(base64Encoded: signatureText),
            signature.count == 64,
            key.isValidSignature(signature, for: data)
      else {
        throw SignatureTestError.invalid("Signature verification failed: \(filename)")
      }
    }
    print("PASS: CryptoKit verifies the Node.js update signatures.")
  }

  private static func decodeBase64URL(_ value: String) throws -> Data {
    var normalized = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while normalized.count % 4 != 0 { normalized.append("=") }
    guard let data = Data(base64Encoded: normalized), data.count == 32 else {
      throw SignatureTestError.invalid("Invalid Ed25519 public key.")
    }
    return data
  }
}
