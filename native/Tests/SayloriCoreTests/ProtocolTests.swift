import XCTest
@testable import SayloriCore
import AudioRing
import CoreAudio
final class ProtocolTests:XCTestCase {
    func testStartGoldenWire() throws {
        let data=ASTProtocol.request(event:100,session:"s")
        // Wire fixture derived independently from the official AST field schema.
        XCTAssertEqual(data.map{String(format:"%02x",$0)}.joined(),"0a033201731064220c220370636d38807d40104801320d0a037332741202656e1a027a68")
        let top=try Proto.parse(data)
        let source=try Proto.parse(try XCTUnwrap(top.first{$0.number==4}).data)
        XCTAssertEqual(source.first{$0.number==7}?.integer,16000)
    }
    func testAudioIsBinaryFieldFourteen() throws {
        let audio=Data([0,255,128,3])
        let top=try Proto.parse(ASTProtocol.request(event:200,session:"s",audio:audio))
        let source=try Proto.parse(try XCTUnwrap(top.first{$0.number==4}).data)
        XCTAssertEqual(source.first{$0.number==14}?.data,audio)
    }
    func testMalformedMessagesRejected() {
        for bytes:[UInt8] in [[0x22,0xff],[0x22,5,1],[0],[0x80],[0x0b],Array(repeating:0xff,count:11)] {
            XCTAssertThrowsError(try Proto.parse(Data(bytes)))
        }
    }
    func testUnknownFieldForwardCompatibility() throws {
        let data=Proto.number(2,654)+Proto.string(4,"你好")+Proto.string(100,"future")
        let response=try ASTEvent(data:data)
        XCTAssertEqual(response.type,654);XCTAssertEqual(response.text,"你好")
    }
    func testOversizedResponseIntegersThrowInsteadOfCrashing() {
        for field in [2,5,6] {
            XCTAssertThrowsError(try ASTEvent(data:Proto.number(field,UInt64.max)))
        }
        XCTAssertThrowsError(try ASTEvent(data:Proto.bytes(1,Proto.number(3,UInt64.max))))
    }
    func testPartialAndFinalDoNotDuplicate() throws {
        var state=CaptionState()
        func event(_ type:Int,_ text:String="")throws->ASTEvent{try ASTEvent(data:Proto.number(2,UInt64(type))+Proto.string(4,text))}
        try state.apply(event(653));try state.apply(event(654,"今天"));try state.apply(event(654,"开会"));try state.apply(event(655,"今天开会。"))
        XCTAssertEqual(state.translation,"今天开会。");XCTAssertTrue(state.isFinal)
        try state.apply(event(653));try state.apply(event(654,"今天"));try state.apply(event(655,"今天开会。"))
        XCTAssertEqual(state.translation,"今天开会。");XCTAssertEqual(state.previous,"今天开会。")
    }
    func testProcessedVoiceChannelNeverMixesAuxiliaryChannels() throws {
        let ring=try XCTUnwrap(say_ring_create_channel(4,3,1,0));defer{say_ring_destroy(ring)}
        var samples:[Float]=[0.1,0.9,0.8,-0.2,0.9,0.8]
        samples.withUnsafeMutableBytes{bytes in
            var buffer=AudioBufferList(mNumberBuffers:1,mBuffers:AudioBuffer(mNumberChannels:3,mDataByteSize:UInt32(bytes.count),mData:bytes.baseAddress))
            say_ring_write_frames(ring,&buffer,2)
        }
        var output=[Float](repeating:0,count:4)
        XCTAssertEqual(say_ring_read(ring,&output,4),2)
        XCTAssertEqual(Array(output.prefix(2)),[0.1,-0.2])
    }
    func testTapUsesActualFrameLengthNotBufferCapacity() throws {
        let ring=try XCTUnwrap(say_ring_create(4,1,0));defer{say_ring_destroy(ring)}
        var samples:[Float]=[0.25,0.5,99,99,99,99,99,99]
        samples.withUnsafeMutableBytes{bytes in
            var buffer=AudioBufferList(mNumberBuffers:1,mBuffers:AudioBuffer(mNumberChannels:1,mDataByteSize:UInt32(bytes.count),mData:bytes.baseAddress))
            say_ring_write_frames(ring,&buffer,2)
        }
        var output=[Float](repeating:0,count:4)
        XCTAssertEqual(say_ring_read(ring,&output,4),2)
        XCTAssertEqual(Array(output.prefix(2)),[0.25,0.5])
        XCTAssertEqual(say_ring_overflow(ring),0)
    }
    func testRingMixesAndDetectsOverflow() throws {
        let ring=try XCTUnwrap(say_ring_create(4,2,1));defer{say_ring_destroy(ring)}
        var samples:[Float]=[0.4,0.2,-0.4,-0.2,1,1]
        samples.withUnsafeMutableBytes{bytes in
            var buffer=AudioBufferList(mNumberBuffers:1,mBuffers:AudioBuffer(mNumberChannels:2,mDataByteSize:UInt32(bytes.count),mData:bytes.baseAddress))
            say_ring_write_frames(ring,&buffer,Int.max)
        }
        var result=[Float](repeating:0,count:4)
        XCTAssertEqual(say_ring_read(ring,&result,2),2)
        XCTAssertEqual(result[0],0.3,accuracy:0.0001);XCTAssertEqual(result[1],-0.3,accuracy:0.0001)
        XCTAssertEqual(say_ring_read(ring,&result,4),1);XCTAssertEqual(result[0],1)
        for _ in 0..<2{samples.withUnsafeMutableBytes{bytes in
            var buffer=AudioBufferList(mNumberBuffers:1,mBuffers:AudioBuffer(mNumberChannels:2,mDataByteSize:UInt32(bytes.count),mData:bytes.baseAddress))
            say_ring_write_frames(ring,&buffer,Int.max)
        }}
        XCTAssertEqual(say_ring_overflow(ring),1)
        say_ring_discard(ring)
        XCTAssertEqual(say_ring_overflow(ring),0)
        XCTAssertEqual(say_ring_read(ring,&result,4),0)
    }
}
