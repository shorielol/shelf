import AppKit
import ShelfCore
import SwiftUI

/// Made-up content for `--snapshot` renders, so README images show widgets doing their job.
/// The track, its lyrics and its cover are invented for Shelf.
enum DemoContent {
    static let track = Track(id: "demo:slow-orbit", title: "Slow Orbit", artist: "The Night Shelf", album: "Desk Lights", duration: 214)

    static let lyrics = """
    [00:41.00]Streetlights hum a quiet tune
    [00:46.40]the kettle clicks, the room goes blue
    [00:52.00]
    [00:58.80]<00:58.80>I <00:59.20>keep <00:59.60>the <00:59.90>record <01:00.50>turning <01:01.60>slow
    [01:04.20]so the night won't know it's late
    [01:09.00]let the needle find the groove
    [01:14.30]and stay a little longer
    """

    static let weatherJSON = """
    {"current":{"temperature_2m":19.4,"apparent_temperature":18.6,"weather_code":2,"is_day":1,"wind_speed_10m":11.0,"relative_humidity_2m":64},
     "hourly":{"time":["2026-11-05T15:00","2026-11-05T16:00","2026-11-05T17:00","2026-11-05T18:00","2026-11-05T19:00","2026-11-05T20:00"],
               "temperature_2m":[19.4,19.0,18.1,16.9,15.8,15.2],"weather_code":[2,2,3,61,61,3],"precipitation_probability":[5,10,30,60,55,20]},
     "daily":{"time":["2026-11-05","2026-11-06","2026-11-07","2026-11-08","2026-11-09"],"weather_code":[2,61,3,0,1],
              "temperature_2m_max":[20.1,17.4,18.0,21.2,20.6],"temperature_2m_min":[13.2,12.8,11.9,12.4,13.0],
              "sunrise":["2026-11-05T07:19","2026-11-06T07:20","2026-11-07T07:21","2026-11-08T07:22","2026-11-09T07:23"],
              "sunset":["2026-11-05T17:31","2026-11-06T17:30","2026-11-07T17:29","2026-11-08T17:28","2026-11-09T17:27"]}}
    """

    static func load(into model: AppModel) async {
        let snapshot = NowPlayingSnapshot(source: .music, track: track, isPlaying: true, position: 61.0, artworkURL: nil)
        await model.nowPlaying.loadDemo(snapshot, artwork: cover())
        model.lyrics.loadDemo(Lyrics(kind: .synced, source: lyrics, duration: track.duration), trackID: track.id)
        if let report = try? OpenMeteoClient.decode(Data(weatherJSON.utf8)) {
            model.weather.loadDemo(report, place: .init(name: "Lisbon", latitude: 38.72, longitude: -9.14))
        }
    }

    /// A sunset cover: ember bands, a pale sun, and a dark horizon. Drawn here, not taken from anywhere.
    /// Nonisolated because palette extraction rasterises the image off the main actor.
    nonisolated static func cover(side: CGFloat = 600) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let bands: [NSColor] = [
                NSColor(red: 0.20, green: 0.07, blue: 0.10, alpha: 1), NSColor(red: 0.55, green: 0.13, blue: 0.13, alpha: 1),
                NSColor(red: 0.85, green: 0.30, blue: 0.18, alpha: 1), NSColor(red: 0.95, green: 0.55, blue: 0.27, alpha: 1),
                NSColor(red: 0.98, green: 0.78, blue: 0.48, alpha: 1),
            ]
            NSGradient(colors: bands)?.draw(in: rect, angle: -90)
            NSColor(red: 1, green: 0.93, blue: 0.80, alpha: 0.92).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - side * 0.2, y: side * 0.28, width: side * 0.4, height: side * 0.4)).fill()
            for i in 0..<6 {
                NSColor(red: 0.2, green: 0.07, blue: 0.1, alpha: 0.85).setFill()
                NSRect(x: 0, y: side * 0.28 + CGFloat(i) * side * 0.035, width: side, height: side * 0.012 + CGFloat(i) * 0.6).fill()
            }
            NSColor(red: 0.12, green: 0.05, blue: 0.08, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: side, height: side * 0.28).fill()
            return true
        }
    }
}
