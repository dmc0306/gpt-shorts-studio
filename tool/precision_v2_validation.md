# v0.21.15+74 Original-source precision verification

Source package: `shorts-studio-source.zip` (packaged by `tool/patch_precision_v2.py`).

## Expected behavior

- A user-confirmed sample mapping, YouTube Shorts `NPom9sHH2J0` to `https://vt.tiktok.com/ZSp11jbJd/`, remains a manually established ground-truth example, not an automated discovery success.
- Direct frame/image evidence determines candidate ordering. Matching YouTube duration is a prerequisite for downloading, not evidence that it is the same video.
- Automatic visual confirmation requires at least 3 visually distinct, chronologically ordered scene matches using the corresponding OCR-free crop in the reference and candidate.
- A repeated static frame, swapped crop region, reversed sequence, or repeated candidate timestamp must not count toward the 3-scene threshold.
- Persistent text in the middle of a candidate is included in existing overlay suspicion checks.
- User-confirmed originals and rejected candidate URLs remain in local state. No unrelated app features are removed.

## Validation

Run `flutter analyze`, `flutter test`, build the fixed-signed Android APK and verify signing in `.github/workflows/android.yml`. The GitHub Actions push from the packaging bot does not itself trigger workflows, so this documentation commit triggers an APK build against the **new packaged ZIP**, instead of the old source.

## Limits

The stricter filter reduces false-positive acceptance but may reduce recall. It does not change Google Cloud Vision's indexing coverage or any third-party stream availability restrictions. Real-world precision and recall remain to be measured on diverse user-labeled original/non-original video pairs.
