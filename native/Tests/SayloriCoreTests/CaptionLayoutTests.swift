import XCTest
@testable import SayloriCore

final class CaptionLayoutTests:XCTestCase {
    func testAllEdgesAndCornersAndContentHitAreas(){
        let size=CGSize(width:720,height:500)
        let cases:[(CGPoint,CaptionEdges)]=[(CGPoint(x:2,y:250),.left),(CGPoint(x:718,y:250),.right),(CGPoint(x:360,y:2),.bottom),(CGPoint(x:360,y:498),.top),(CGPoint(x:10,y:10),[.bottom,.left]),(CGPoint(x:710,y:10),[.bottom,.right]),(CGPoint(x:10,y:490),[.top,.left]),(CGPoint(x:710,y:490),[.top,.right])]
        for (point,edges) in cases{XCTAssertEqual(CaptionEdges.hit(point,size:size),edges)}
        XCTAssertTrue(CaptionEdges.hit(CGPoint(x:360,y:250),size:size).isEmpty)
        XCTAssertTrue(CaptionEdges.hit(CGPoint(x:680,y:475),size:size).isEmpty)
    }
    func testLeftBottomResizeKeepsOppositeCornerAtMinimum(){
        let frame=CGRect(x:100,y:200,width:720,height:500)
        let result=CaptionEdges([.left,.bottom]).resizing(frame,delta:CGSize(width:600,height:400),minimum:CGSize(width:400,height:300),maximum:CGSize(width:1600,height:1100))
        XCTAssertEqual(result.size,CGSize(width:400,height:300))
        XCTAssertEqual(result.maxX,frame.maxX);XCTAssertEqual(result.maxY,frame.maxY)
    }
    func testTopRightResizeKeepsOppositeCornerAtMaximum(){
        let frame=CGRect(x:100,y:200,width:720,height:500)
        let result=CaptionEdges([.top,.right]).resizing(frame,delta:CGSize(width:2000,height:2000),minimum:CGSize(width:400,height:300),maximum:CGSize(width:1600,height:1100))
        XCTAssertEqual(result.origin,frame.origin);XCTAssertEqual(result.size,CGSize(width:1600,height:1100))
    }
    func testHistoryFitsHeightAndRetainsLongLatestEntry(){
        let heights=[60.0,70,80,60,50,60]
        XCTAssertEqual(CaptionHistoryLayout.visibleCount(heights:heights,available:100),1)
        XCTAssertEqual(CaptionHistoryLayout.visibleCount(heights:heights,available:220),3)
        XCTAssertEqual(CaptionHistoryLayout.visibleCount(heights:heights,available:600),6)
        XCTAssertEqual(CaptionHistoryLayout.visibleCount(heights:[200],available:60),1)
        XCTAssertEqual(CaptionHistoryLayout.visibleCount(heights:[],available:60),0)
    }
}
