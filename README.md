# Stashlog: Home Inventory

**A free, private, open-source home inventory app for iPhone.** · [Website](https://rshamilton.github.io/Stashlog/) · [Privacy](https://rshamilton.github.io/Stashlog/privacy.html)

Film a slow walkthrough of each room, and Stashlog finds your belongings using on-device AI. Confirm the suggestions, add serial numbers and receipts, then export an insurance-ready PDF.

- **100% free.** No in-app purchases, no subscription, no ads.
- **Private by design.** Videos and photos are processed on your iPhone. Stashlog has no servers, no account and no analytics. Nothing is uploaded.
- **Video walkthrough → item list.** Film a room, then review the items Stashlog recognized, with quantities and photos.
- **Reads labels and receipts.** Photograph a nameplate or receipt to fill in brand, model, serial number, price and purchase date. All text is read on-device.
- **Insurance-ready PDF.** A room-by-room report with photos, serial numbers, values, totals and attached receipts. CSV export too.
- **Works offline.**
- **Open source (GPLv3).** Read the code and check every claim above.

## Who it's for
Renters and homeowners who want proof of what they own *before* a fire, flood, burglary or move, and who don't want to upload a video of their home to someone's cloud.

## How it works
| Step | On-device technology |
|---|---|
| Sample frames from the walkthrough video | `AVAssetImageGenerator` |
| Find object regions in each frame | Vision `GenerateObjectnessBasedSaliencyImageRequest` |
| Recognize what each object is | Vision `ClassifyImageRequest`, filtered to ~200 insurable item types ([`LabelCatalog`](Stashlog/Scanning/LabelCatalog.swift)) |
| Merge sightings across frames, estimate quantity | [`ScanAggregator`](Stashlog/Scanning/ScanAggregator.swift) |
| Read serial-number labels and receipts | Vision `RecognizeTextRequest` + pattern matching, plus Apple's **on-device** Foundation Models where available (never Private Cloud Compute) |
| Build the report | `UIGraphicsPDFRenderer` |

## Requirements
- iOS 26 or later
- Label reading uses Apple Intelligence where the device supports it, and falls back to pattern matching otherwise.

## Building
```bash
brew install xcodegen   # only needed if you change project.yml
xcodegen generate
open Stashlog.xcodeproj
```
Run the tests with ⌘U, or from the command line:
```bash
xcodebuild -scheme Stashlog -destination 'platform=iOS Simulator,name=iPhone 13' test
```

## Roadmap
- [ ] iCloud sync, using your private iCloud database (still no Stashlog servers)
- [ ] Live camera scanning mode with on-screen boxes
- [ ] LiDAR room scan (RoomPlan) for furniture and appliances
- [ ] Multiple properties
- [ ] Warranty expiry reminders

## License
Stashlog is licensed under the [GNU GPL v3](LICENSE). The **Stashlog name and app icon are not covered by the license**. Forks must use their own name and icon.
