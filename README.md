# MouseBehaviorAnalysis

MATLAB software for tracking mice in separate open-field arenas and quantifying locomotor activity and zone occupancy.

## Requirements

- MATLAB desktop. The original distribution lists MATLAB R2022b on macOS as its tested environment.
- Image Processing Toolbox.
- Statistics and Machine Learning Toolbox.
- Java support for spreadsheet export.

Video decoding and encoding depend on the codecs available on the operating system.

## Installation

Download the following files and keep their directory structure intact:

```text
MouseBehaviorAnalysis.m
xlwrite.m
poi_library/
README.md
THIRD_PARTY_NOTICES.md
```

Include all JAR files and the LICENSE file in `poi_library/`. In MATLAB, set the folder containing `MouseBehaviorAnalysis.m` as the **Current Folder**. The spreadsheet exporter loads its Java libraries relative to this folder. No compilation is required.

## Usage

Run the following in the MATLAB Command Window:

```matlab
MouseBehaviorAnalysis
```

1. Select a video (`.mov`, `.wmv`, `.mp4` or `.avi`, subject to codec support).
2. Select the mouse/background combination: a dark mouse on a light background, or a light mouse on a dark background.
3. Choose trajectory colours and line width.
4. Configure zero to four rectangular analysis zones.
5. Select a threshold from the preview images. The animal should remain visible while background regions are suppressed.
6. Confirm the threshold, minimum object area in pixels, mouse count, first and last frames, and frame sampling interval.
7. Draw one arena rectangle per mouse. Double-click each rectangle to confirm it.
8. After analysis, optionally generate a tracking-check movie and specify its final source frame.

Each arena should contain one mouse. Inspect the tracking-check movie to assess tracking quality. The program closes existing figures and clears the Command Window when started.

## Calibration and analysis settings

Set the physical arena size in the **User settings** block before running the program. The default is a square arena with a side length of **400 mm** and a **200 × 200 mm** centre zone, positioned 100 mm from each wall. Adjust these settings to match the experiment.

Zone X and Y coordinates are measured in millimetres from the upper-left corner of the arena rectangle. Zone width and height are also in millimetres. Selecting zero zones disables zone-occupancy summaries and dashed zone outlines.

| Parameter | Meaning | Initial value |
|---|---|---|
| Threshold | Intensity threshold for segmentation | Selected interactively |
| Minimal pixels | Minimum connected-object area retained before ROI measurements | 200 pixels |
| Mouse number | Number of arena ROIs | 1 |
| Start frame | First source frame to analyse | 1 |
| Last frame | Last source frame to analyse | Estimated video frame count |
| Frame step | Analyse every specified number of frames | 1 |

Record the settings used for each video, including threshold, minimum object area and arena calibration. The result MAT file does not store the threshold or minimum-object-area setting.

## Outputs

Results are saved beside the input video, in a folder with the same name as the video without its extension.

| Output | Contents |
|---|---|
| `*_result.mat` | Tracking coordinates, body-shape measurements and stored analysis settings |
| `*_result.xls` | Coordinates, incremental and cumulative travel distance, and zone-occupancy summaries |
| `*_summary.tif` | Trajectory plot and cumulative travel-distance plot |
| `*_orientation.tif` | Body-shape distribution plots |
| `*_result.mp4` or `*_result.avi` | Optional tracking-check movie |

Coordinates and shape lengths are in pixels; object area is in pixels squared. Calibrated incremental distance is in millimetres, cumulative distance in metres, and time in seconds.

**Existing results are reused.** An existing result MAT file causes tracking to be skipped, and an existing result XLS file can cause summary export to be skipped. To analyse the video with different settings while preserving earlier results, use a copy of the video in a separate directory.

## Measurement conventions

The program retains the following analysis conventions:

- Thresholded images are passed to `regionprops` as numeric 0/255 label images; disconnected foreground pixels with the same label are measured together.
- Centroids are rounded down to integer pixel coordinates. Distance conversion uses the mean of the horizontal and vertical millimetres-per-pixel factors.
- When tracking fails, the preceding position and shape measurements are reused; an initial failure uses the arena midpoint and zero shape values. These substituted values remain in subsequent summaries.
- Each sampled frame contributes `frame step / frame rate` seconds to occupancy. Zone boundaries are included, and overlapping zones are counted independently.
- The outside-zone fraction labelled as thigmotaxis in the spreadsheet refers to the first configured analysis zone.

Time calculations assume a constant frame rate. The direct AVI/MJPEG reader uses heuristic frame indexing and a 30 fps fallback if frame-rate extraction fails; verify frame count and frame rate against the recording metadata.

## Troubleshooting

- **Poor detection:** check mouse/background polarity, threshold, minimum object area and arena placement.
- **Spreadsheet export fails:** check that `xlwrite.m` and the complete `poi_library/` folder are present and that the MATLAB Current Folder is the program folder.
- **Video output fails:** the program attempts MPEG-4 output first, then Motion JPEG AVI. Codec availability varies by operating system.
- **Changed settings appear to have no effect:** check whether the program is reusing previously saved results.

## Attribution

This program is adapted from Mouse Activity Analyzer / MouseActivity by Renzhi Han. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for source attribution and third-party license information.

Zhang C, Li H, Han R. An open-source video tracking system for mouse locomotor activity analysis. *BMC Research Notes*. 2020;13:48. [doi:10.1186/s13104-020-4916-6](https://doi.org/10.1186/s13104-020-4916-6).
