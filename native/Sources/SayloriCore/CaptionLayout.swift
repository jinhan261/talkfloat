import Foundation

public struct CaptionEdges:OptionSet,Sendable {
    public let rawValue:Int
    public init(rawValue:Int){self.rawValue=rawValue}
    public static let left=Self(rawValue:1),right=Self(rawValue:2),bottom=Self(rawValue:4),top=Self(rawValue:8)
    public static func hit(_ point:CGPoint,size:CGSize)->Self {
        let corner:CGFloat=20,edge:CGFloat=7
        var result:Self=[]
        let nearHorizontal=point.y<corner || point.y>size.height-corner
        let nearVertical=point.x<corner || point.x>size.width-corner
        if point.x<(nearHorizontal ? corner:edge){result.insert(.left)}
        if point.x>size.width-(nearHorizontal ? corner:edge){result.insert(.right)}
        if point.y<(nearVertical ? corner:edge){result.insert(.bottom)}
        if point.y>size.height-(nearVertical ? corner:edge){result.insert(.top)}
        return result
    }
    public func resizing(_ frame:CGRect,delta:CGSize,minimum:CGSize,maximum:CGSize)->CGRect {
        var result=frame
        if contains(.left) || contains(.right){
            result.size.width=max(minimum.width,min(maximum.width,frame.width+(contains(.left) ? -delta.width:delta.width)))
            if contains(.left){result.origin.x=frame.maxX-result.width}
        }
        if contains(.bottom) || contains(.top){
            result.size.height=max(minimum.height,min(maximum.height,frame.height+(contains(.bottom) ? -delta.height:delta.height)))
            if contains(.bottom){result.origin.y=frame.maxY-result.height}
        }
        return result
    }
}

public enum CaptionHistoryLayout {
    /// Keep whole recent entries when possible; a single long entry stays scrollable.
    public static func visibleCount(heights:[Double],available:Double,spacing:Double=14)->Int {
        guard !heights.isEmpty else{return 0}
        var used=0.0,count=0
        for height in heights.reversed(){
            let addition=height+(count==0 ? 0:spacing)
            if count>0 && used+addition>available{break}
            used+=addition;count+=1
        }
        return count
    }
}
