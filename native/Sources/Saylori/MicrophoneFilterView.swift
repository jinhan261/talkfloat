import SwiftUI
import AppKit
import SayloriCore

struct MicrophoneFilterView:View {
    @ObservedObject var model:SessionModel
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            HStack {
                Text("背景声过滤").font(.system(size:11,weight:.medium))
                Spacer()
                Toggle("背景声过滤",isOn:$model.microphoneNearField)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            if model.microphoneNearField {
                HStack {
                    Text("过滤门限").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.microphoneThresholdDB.formatted(.number.precision(.fractionLength(0...1)))) dB").monospacedDigit().foregroundStyle(.secondary)
                }.font(.system(size:10.5))
                MicrophoneThresholdSlider(value:$model.microphoneThresholdDB).frame(height:18)
                    .help("向右提高门限，过滤更多小声讲话；你的声音收不到时向左调。数值是处理后麦克风的 dBFS，不是环境声压分贝。")
                HStack {Text("宽松");Spacer();Text("严格")}
                    .font(.system(size:10)).foregroundStyle(.secondary).padding(.top,-4)
                if model.microphoneReady {
                    Canvas{context,size in
                        let y=(size.height-4)/2
                        let width=size.width
                        let amount=max(0,min(1,(model.microphoneRMSDB+60)/60))
                        let marker=max(0,min(1,(model.microphoneThresholdDB+60)/60))
                        context.fill(Path(roundedRect:CGRect(x:0,y:y,width:width,height:4),cornerRadius:2),with:.color(.primary.opacity(0.08)))
                        context.fill(Path(roundedRect:CGRect(x:0,y:y,width:width*amount,height:4),cornerRadius:2),with:.color(model.microphonePassing ? Brand.accent:.secondary.opacity(0.5)))
                        context.fill(Path(roundedRect:CGRect(x:width*marker-1,y:0,width:2,height:size.height),cornerRadius:1),with:.color(.primary.opacity(0.6)))
                    }.frame(height:10).accessibilityHidden(true)
                    HStack(spacing:4){
                        Text(model.microphoneRMSDB < -60 ? "低于 −60 dB":"\(Int(model.microphoneRMSDB.rounded())) dB").monospacedDigit()
                        Spacer(minLength:2)
                        Text(model.microphoneGateLabel)
                    }.font(.system(size:10.5)).foregroundStyle(.secondary)
                        .accessibilityElement(children:.combine)
                }else{
                    Text("开始后显示实时音量").font(.system(size:10.5)).foregroundStyle(.secondary)
                }
            }
        }.padding(.leading,50).padding(.trailing,12).padding(.bottom,12)
            .help("低于门限的声音不进入识别，发言起止有短暂保护。门限不能区分同样响亮的两个人。")
    }
}

/// Keep the native macOS track, with predictable focus and 1 dB keyboard/AX steps.
private struct MicrophoneThresholdSlider:NSViewRepresentable {
    @Binding var value:Double
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeNSView(context:Context)->Control {
        let control=Control(value:value,minValue:NearSpeechGate.thresholdRange.lowerBound,maxValue:NearSpeechGate.thresholdRange.upperBound,target:context.coordinator,action:#selector(Coordinator.changed(_:)))
        control.controlSize = .small;control.isContinuous=true;control.numberOfTickMarks=0
        control.setAccessibilityLabel("麦克风过滤门限")
        control.setAccessibilityHelp("向右过滤更严格；左右箭头每次调节 1 分贝。")
        return control
    }
    func updateNSView(_ control:Control,context:Context){context.coordinator.parent=self;control.doubleValue=value}
    final class Coordinator:NSObject {
        var parent:MicrophoneThresholdSlider
        init(_ parent:MicrophoneThresholdSlider){self.parent=parent}
        @objc func changed(_ sender:NSSlider){parent.value=sender.doubleValue}
    }
    final class Control:NSSlider {
        override var acceptsFirstResponder:Bool{true}
        override func mouseDown(with event:NSEvent){window?.makeFirstResponder(self);super.mouseDown(with:event)}
        override func keyDown(with event:NSEvent){
            if event.keyCode==123{adjust(-1)}else if event.keyCode==124{adjust(1)}else{super.keyDown(with:event)}
        }
        override func accessibilityPerformIncrement()->Bool{adjust(1);return true}
        override func accessibilityPerformDecrement()->Bool{adjust(-1);return true}
        private func adjust(_ delta:Double){doubleValue=NearSpeechGate.boundedThreshold(doubleValue.rounded()+delta);sendAction(action,to:target)}
    }
}
