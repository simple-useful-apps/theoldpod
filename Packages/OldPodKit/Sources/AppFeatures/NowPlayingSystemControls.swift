#if os(iOS)
    import AVKit
    import MediaPlayer
    import SwiftUI

    /// The system volume slider. It draws nothing in the Simulator, which has
    /// no hardware volume; on a device it tracks the side buttons.
    struct SystemVolumeSlider: UIViewRepresentable {
        func makeUIView(context _: Context) -> MPVolumeView {
            let view = MPVolumeView(frame: .zero)
            // The AirPlay route button sits beside the slider as its own view.
            view.showsRouteButton = false
            return view
        }

        func updateUIView(_: MPVolumeView, context _: Context) {}
    }

    /// The system AirPlay / audio-route picker button.
    struct AudioRoutePicker: UIViewRepresentable {
        func makeUIView(context _: Context) -> AVRoutePickerView {
            let view = AVRoutePickerView(frame: .zero)
            view.prioritizesVideoDevices = false
            return view
        }

        func updateUIView(_: AVRoutePickerView, context _: Context) {}
    }
#endif
