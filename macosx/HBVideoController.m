/*  HBVideoController.m $

 This file is part of the HandBrake source code.
 Homepage: <http://handbrake.fr/>.
 It may be used under the terms of the GNU General Public License. */

#import "HBVideoController.h"

@import HandBrakeKit;

static void *HBVideoControllerContext = &HBVideoControllerContext;

@interface HBVideoController () {
    // Framerate Radio Button Framerate Controls
    IBOutlet NSButton *fFramerateVfrPfrButton;

    // Video Encoder
    IBOutlet NSSlider *fVidQualitySlider;

    // Encoder options views
    IBOutlet NSView *fPresetView;
    IBOutlet NSView *fSimplePresetView;

    IBOutlet NSTextField *fEncoderOptionsLabel;

    // x264/x265 Presets Box
    IBOutlet NSBox          *fPresetsBox;
    IBOutlet NSSlider       *fPresetsSlider;

    // Text Field to show the expanded opts from unparse()
    IBOutlet NSTextField *fDisplayX264PresetsUnparseTextField;
}

@property (nonatomic, weak) IBOutlet NSTextField *additionalsOptions;

@property (nonatomic) BOOL presetViewEnabled;
@property (nonatomic) NSColor *labelColor;

@end

@implementation HBVideoController

- (instancetype)init
{
    self = [super initWithNibName:@"Video" bundle:nil];
    if (self)
    {
        _labelColor = [NSColor disabledControlTextColor];

        // Observe the x264 slider granularity, to update the slider when the pref is changed.
        [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                                  forKeyPath:@"values.HBx264CqSliderFractional"
                                                                     options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                                                                     context:HBVideoControllerContext];

        // Observer a bunch of HBVideo properties to update the UI.
        [self addObserver:self forKeyPath:@"video.encoder" options:NSKeyValueObservingOptionInitial context:HBVideoControllerContext];
        [self addObserver:self forKeyPath:@"video.frameRate" options:NSKeyValueObservingOptionInitial context:HBVideoControllerContext];
        [self addObserver:self forKeyPath:@"video.quality" options:NSKeyValueObservingOptionInitial context:HBVideoControllerContext];
        [self addObserver:self forKeyPath:@"video.preset" options:NSKeyValueObservingOptionInitial context:HBVideoControllerContext];
        [self addObserver:self forKeyPath:@"video.unparseOptions" options:NSKeyValueObservingOptionInitial context:HBVideoControllerContext];
    }

    return self;
}

- (void)setVideo:(HBVideo *)video
{
    _video = video;

    if (video)
    {
        self.labelColor = [NSColor controlTextColor];
    }
    else
    {
        self.labelColor = [NSColor disabledControlTextColor];
    }

    [self enableEncoderOptionsWidgets:(video != nil)];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == HBVideoControllerContext)
    {
        if ([keyPath isEqualToString:@"video.encoder"])
        {
            [self switchPresetView];
            [self setupQualitySlider];
        }
        else if ([keyPath isEqualToString:@"video.frameRate"])
        {
            // Hide and set the PFR Checkbox to OFF if we are set to Same as Source
            // Depending on whether or not Same as source is selected modify the title for
            // fFramerateVfrPfrCell
            if (self.video.frameRate == 0) // We are Same as Source
            {
                [fFramerateVfrPfrButton setTitle:NSLocalizedString(@"Variable Framerate", @"Video -> Framerate")];
            }
            else
            {
                [fFramerateVfrPfrButton setTitle:NSLocalizedString(@"Peak Framerate (VFR)", @"Video -> Framerate")];
            }
        }
        else if ([keyPath isEqualToString:@"video.quality"])
        {
            fVidQualitySlider.accessibilityValueDescription = [NSString stringWithFormat:@"%@ %.2f", self.video.constantQualityLabel, self.video.quality];;
        }
        else if ([keyPath isEqualToString:@"video.preset"])
        {
            fPresetsSlider.accessibilityValueDescription = self.video.preset;
        }
        else if ([keyPath isEqualToString:@"video.unparseOptions"])
        {
            if ([self.video isUnparsedSupported:self.video.encoder])
            {
                fDisplayX264PresetsUnparseTextField.stringValue = [NSString stringWithFormat:@"x264 Unparse: %@", self.video.unparseOptions];
            }
            else
            {
                fDisplayX264PresetsUnparseTextField.stringValue = @"";
            }
        }
        else if ([keyPath isEqualToString:@"values.HBx264CqSliderFractional"])
        {
            [self setupQualitySlider];
        }
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Interface setup

/*
 * Use this method to setup the quality slider for cq/rf values depending on
 * the video encoder selected.
 */
- (void)setupQualitySlider
{
    int direction = 1;
    float minValue = 0, maxValue = 0, granularity = 0;
    [self.video qualityLimitsForEncoder:self.video.encoder low:&minValue high:&maxValue granularity:&granularity direction:&direction];

    if (granularity < 1.0f)
    {
         // Encoders that allow fractional CQ values often have a low granularity
         // which makes the slider hard to use, so use a value from preferences.
        granularity = 1.0f / [[NSUserDefaults standardUserDefaults]
                       integerForKey:@"HBx264CqSliderFractional"];
    }
    fVidQualitySlider.minValue = minValue;
    fVidQualitySlider.maxValue = maxValue;

    NSInteger numberOfTickMarks = (NSInteger)((maxValue - minValue) * (1.0f / granularity)) + 1;
    fVidQualitySlider.numberOfTickMarks = numberOfTickMarks;

    // Replace the slider transformer with a new one,
    // configured with the new max/min/direction values.
    [fVidQualitySlider unbind:@"value"];
    HBQualityTransformer *transformer = [[HBQualityTransformer alloc] initWithReversedDirection:(direction != 0) min:minValue max:maxValue];
    [fVidQualitySlider bind:@"value" toObject:self withKeyPath:@"self.video.quality" options:@{NSValueTransformerBindingOption: transformer}];
}

#pragma mark - Video x264/x265 Presets

/**
 *  Shows/hides the right preset view for the current video encoder.
 */
- (void)switchPresetView
{
    if ([self.video isPresetSystemSupported:self.video.encoder])
    {
        fPresetsBox.contentView = fPresetView;
        [self setupPresetsSlider];
    }
    else if ([self.video isSimpleOptionsPanelSupported:self.video.encoder])
    {
        fPresetsBox.contentView = fSimplePresetView;
    }
    else
    {
        fPresetsBox.contentView = nil;
    }
}

/**
 *  Enables/disables the preset panel.
 */
- (void)enableEncoderOptionsWidgets:(BOOL)enable
{
    self.presetViewEnabled = enable;
}

/**
 *  Setup the presets slider with the right
 *  number of ticks.
 */
- (void)setupPresetsSlider
{
    // setup the preset slider
    [fPresetsSlider setMaxValue:self.video.presets.count - 1];
    [fPresetsSlider setNumberOfTickMarks:self.video.presets.count];

    // Bind the slider value to a custom value transformer,
    // done here because it can't be done in IB.
    [fPresetsSlider unbind:@"value"];
    HBPresetsTransformer *transformer = [[HBPresetsTransformer alloc] initWithEncoder:self.video.encoder];
    [fPresetsSlider bind:@"value" toObject:self withKeyPath:@"self.video.preset" options:@{NSValueTransformerBindingOption: transformer}];
}


@end
