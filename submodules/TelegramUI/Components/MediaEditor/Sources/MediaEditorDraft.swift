import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import PersistentStringHash
import Postbox
import AccountContext

public struct MediaEditorResultPrivacy: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case type
        case privacy
        case peers
        case timeout
        case archive
    }
    
    public let privacy: EngineStoryPrivacy
    public let timeout: Int
    public let archive: Bool
    
    public init(
        privacy: EngineStoryPrivacy,
        timeout: Int,
        archive: Bool
    ) {
        self.privacy = privacy
        self.timeout = timeout
        self.archive = archive
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.privacy = try container.decode(EngineStoryPrivacy.self, forKey: .privacy)
        self.timeout = Int(try container.decode(Int32.self, forKey: .timeout))
        self.archive = try container.decode(Bool.self, forKey: .archive)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
    
        try container.encode(self.privacy, forKey: .privacy)
        try container.encode(Int32(self.timeout), forKey: .timeout)
        try container.encode(self.archive, forKey: .archive)
    }
}

public final class MediaEditorDraft: Codable, Equatable {
    public static func == (lhs: MediaEditorDraft, rhs: MediaEditorDraft) -> Bool {
        return lhs.path == rhs.path
    }
    
    private enum CodingKeys: String, CodingKey {
        case path
        case isVideo
        case thumbnail
        case dimensionsWidth
        case dimensionsHeight
        case duration
        case values
        case caption
        case privacy
    }
    
    public let path: String
    public let isVideo: Bool
    public let thumbnail: UIImage
    public let dimensions: PixelDimensions
    public let duration: Double?
    public let values: MediaEditorValues
    public let caption: NSAttributedString
    public let privacy: MediaEditorResultPrivacy?
        
    public init(path: String, isVideo: Bool, thumbnail: UIImage, dimensions: PixelDimensions, duration: Double?, values: MediaEditorValues, caption: NSAttributedString, privacy: MediaEditorResultPrivacy?) {
        self.path = path
        self.isVideo = isVideo
        self.thumbnail = thumbnail
        self.dimensions = dimensions
        self.duration = duration
        self.values = values
        self.caption = caption
        self.privacy = privacy
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.path = try container.decode(String.self, forKey: .path)
        self.isVideo = try container.decode(Bool.self, forKey: .isVideo)
        let thumbnailData = try container.decode(Data.self, forKey: .thumbnail)
        if let thumbnail = UIImage(data: thumbnailData) {
            self.thumbnail = thumbnail
        } else {
            fatalError()
        }
        self.dimensions = PixelDimensions(
            width: try container.decode(Int32.self, forKey: .dimensionsWidth),
            height: try container.decode(Int32.self, forKey: .dimensionsHeight)
        )
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        let valuesData = try container.decode(Data.self, forKey: .values)
        if let values = try? JSONDecoder().decode(MediaEditorValues.self, from: valuesData) {
            self.values = values
        } else {
            fatalError()
        }
        self.caption = ((try? container.decode(ChatTextInputStateText.self, forKey: .caption)) ?? ChatTextInputStateText()).attributedText()
        
        if let data = try container.decodeIfPresent(Data.self, forKey: .privacy), let privacy = try? JSONDecoder().decode(MediaEditorResultPrivacy.self, from: data) {
            self.privacy = privacy
        } else {
            self.privacy = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.path, forKey: .path)
        try container.encode(self.isVideo, forKey: .isVideo)
        if let thumbnailData = self.thumbnail.jpegData(compressionQuality: 0.6) {
            try container.encode(thumbnailData, forKey: .thumbnail)
        }
        try container.encode(self.dimensions.width, forKey: .dimensionsWidth)
        try container.encode(self.dimensions.height, forKey: .dimensionsHeight)
        try container.encodeIfPresent(self.duration, forKey: .duration)
        if let valuesData = try? JSONEncoder().encode(self.values) {
            try container.encode(valuesData, forKey: .values)
        }
        let chatInputText = ChatTextInputStateText(attributedText: self.caption)
        try container.encode(chatInputText, forKey: .caption)
        
        if let privacy = self .privacy {
            if let data = try? JSONEncoder().encode(privacy) {
                try container.encode(data, forKey: .privacy)
            } else {
                try container.encodeNil(forKey: .privacy)
            }
        } else {
            try container.encodeNil(forKey: .privacy)
        }
    }
}

private struct MediaEditorDraftItemId {
    public let rawValue: MemoryBuffer
    
    var value: Int64 {
        return self.rawValue.makeData().withUnsafeBytes { buffer -> Int64 in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: Int64.self) else {
                return 0
            }
            return bytes.pointee
        }
    }
    
    init(_ rawValue: MemoryBuffer) {
        self.rawValue = rawValue
    }
    
    init(_ value: Int64) {
        var value = value
        self.rawValue = MemoryBuffer(data: Data(bytes: &value, count: MemoryLayout.size(ofValue: value)))
    }
    
    init(_ value: UInt64) {
        var value = Int64(bitPattern: value)
        self.rawValue = MemoryBuffer(data: Data(bytes: &value, count: MemoryLayout.size(ofValue: value)))
    }
}

public func addStoryDraft(engine: TelegramEngine, item: MediaEditorDraft) {
    let itemId = MediaEditorDraftItemId(item.path.persistentHashValue)
    let _ = engine.orderedLists.addOrMoveToFirstPosition(collectionId: ApplicationSpecificOrderedItemListCollectionId.storyDrafts, id: itemId.rawValue, item: item, removeTailIfCountExceeds: 50).start()
}

public func removeStoryDraft(engine: TelegramEngine, path: String, delete: Bool) {
    if delete {
        try? FileManager.default.removeItem(atPath: fullDraftPath(path))
    }
    let itemId = MediaEditorDraftItemId(path.persistentHashValue)
    let _ = engine.orderedLists.removeItem(collectionId: ApplicationSpecificOrderedItemListCollectionId.storyDrafts, id: itemId.rawValue).start()
}

public func clearStoryDrafts(engine: TelegramEngine) {
    let _ = engine.orderedLists.clear(collectionId: ApplicationSpecificOrderedItemListCollectionId.storyDrafts).start()
}

public func storyDrafts(engine: TelegramEngine) -> Signal<[MediaEditorDraft], NoError> {
    return engine.data.subscribe(TelegramEngine.EngineData.Item.OrderedLists.ListItems(collectionId: ApplicationSpecificOrderedItemListCollectionId.storyDrafts))
    |> map { items -> [MediaEditorDraft] in
        var result: [MediaEditorDraft] = []
        for item in items {
            if let draft = item.contents.get(MediaEditorDraft.self) {
                result.append(draft)
            }
        }
        return result
    }
}

public extension MediaEditorDraft {
    func fullPath() -> String {
        return fullDraftPath(self.path)
    }
}

private func fullDraftPath(_ path: String) -> String {
    return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/storyDrafts/" + path
}
