import Foundation

enum CRXExtractorError: LocalizedError {
    case invalidHeader
    case invalidMagic
    case extractionFailed(String)
    case manifestNotFound

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "Cabeçalho de extensão CRX inválido."
        case .invalidMagic:
            return "Formato de arquivo não reconhecido (esperado CRX3 ou ZIP)."
        case .extractionFailed(let message):
            return "Falha ao extrair extensão: \(message)"
        case .manifestNotFound:
            return "manifest.json não encontrado na extensão."
        }
    }
}

enum CRXExtractor {
    /// Extracts a CRX3 (or raw ZIP) archive into the destination directory.
    static func extract(crxData: Data, to destinationURL: URL) throws {
        guard crxData.count > 16 else {
            throw CRXExtractorError.invalidHeader
        }

        let magic = crxData.subdata(in: 0..<4)
        let crxMagic = Data([0x43, 0x72, 0x32, 0x34]) // "Cr24"
        let zipMagic = Data([0x50, 0x4B, 0x03, 0x04]) // "PK\x03\x04"

        let zipData: Data
        if magic == crxMagic {
            // Read header length at offset 8 (UInt32 little endian)
            let headerLength: UInt32 = crxData.subdata(in: 8..<12).withUnsafeBytes {
                $0.load(as: UInt32.self)
            }
            let zipOffset = 12 + Int(headerLength)
            guard crxData.count > zipOffset else {
                throw CRXExtractorError.invalidHeader
            }
            zipData = crxData.subdata(in: zipOffset..<crxData.count)
        } else if magic == zipMagic {
            zipData = crxData
        } else {
            throw CRXExtractorError.invalidMagic
        }

        try extractZipPayload(zipData, to: destinationURL)
    }

    private static func extractZipPayload(_ zipData: Data, to destinationURL: URL) throws {
        let tempZipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crx_\(UUID().uuidString).zip")

        try zipData.write(to: tempZipURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempZipURL) }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", tempZipURL.path, destinationURL.path]

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Erro desconhecido ao descompactar"
            throw CRXExtractorError.extractionFailed(errorMsg)
        }

        let manifestURL = destinationURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CRXExtractorError.manifestNotFound
        }
    }
}
