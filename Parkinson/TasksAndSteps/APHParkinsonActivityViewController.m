//
//  APHParkinsonActivityViewController.m
//  mPower
//
//  Copyright (c) 2015 Apple, Inc. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "APHParkinsonActivityViewController.h"
#import "APHAppDelegate.h"

    //
    //    keys for the extra step ('Pre-Survey') that;'s injected
    //        into Parkinson Activities to ask the Patient if they
    //        have taken their medications
    //
NSString  *const kMomentInDayStepIdentifier             = @"momentInDay";

NSString  *const kMomentInDayFormat                     = @"momentInDayFormat";

    //
    //    key for Parkinson Stashed Question Result
    //        from 'When Did You Take Your Medicine' Pre-Survey Question
    //
NSString  *const kMomentInDayUserDefaultsKey            = @"MomentInDayUserDefaults";
    //
    //    keys for Parkinson Stashed Question Result Dictionary
    //        from 'When Did You Take Your Medicine' Pre-Survey Question
    //
NSString  *const kMomentInDayChoiceAnswerKey            = @"MomentInDayChoiceAnswer";
NSString  *const kMomentInDayQuestionTypeKey            = @"MomentInDayQuestionType";
NSString  *const kMomentInDayIdentifierKey              = @"MomentInDayIdentifier";
NSString  *const kMomentInDayStartDateKey               = @"MomentInDayStartDate";
NSString  *const kMomentInDayEndDateKey                 = @"MomentInDayEndDate";
NSString  *const kMomentInDayChoiceNoneKey              = @"MomentInDayNoneChoice";

    //
    //    keys for Parkinson Conclusion Step View Controller
    //
NSString  *kConclusionStepThankYouTitle;
NSString  *kConclusionStepViewDashboard;

//
//    elapsed time delay before asking the patient if they took their medications
//
static  NSTimeInterval  kMinimumAmountOfTimeToShowSurvey         = 20.0 * 60.0;
static  NSTimeInterval  kMinimumAmountOfTimeToShowSurveyIfNoMeds = 30.0 * 24.0 * 60.0 * 60.0;

static NSString *kMomentInDayNoneChoice = nil;

@interface APHParkinsonActivityViewController ()

@property  (nonatomic, strong)  NSArray  *stashedSteps;

@end

    //
    //    Common Super-Class for all four Parkinson Task View Controllers
    //

    //
    //    A Parkinson Activity may have an optional step inject at the
    //    beginning of the Activity to ask the patient if they have taken their medications
    //
    //    That extra step is included in the Activity Step Results to be uploaded
    //
    //    The Research Institution requires that this information be supplied even when
    //    the question is not asked, in which case, a cached copy of the most recent
    //    results is used, until such time as a new result may be created
    //
    //    modifyTaskWithPreSurveyStepIfRequired does the optional step injection if needed
    //
    //    stepViewControllerResultDidChange records the most recent copy of the cached result
    //
    //    taskViewController didFinishWithReason uses the cached result if the step results
    //    do not already contain the apropriate step result
    //
    //    the over-ridden  result  method ensures that the cached results are used if they exist
    //
@implementation APHParkinsonActivityViewController

+ (void)initialize
{
    void (^localizeBlock)() = [^{
        
        kMomentInDayNoneChoice = NSLocalizedString(@"I don't take Parkinson medications", @"Timing option text in pre-activity medication timing survey for someone who doesn't take medication.");
        
        //
        //    keys for Parkinson Conclusion Step View Controller
        //
        kConclusionStepThankYouTitle           = NSLocalizedString(@"Thank You!", @"Main text shown to participant upon completion of an activity.");
        kConclusionStepViewDashboard           = NSLocalizedString(@"The results of this activity can be viewed on the dashboard", @"Detail text shown to participant upon completion of an activity.");
    } copy];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NSCurrentLocaleDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull __unused note) {
        localizeBlock();
    }];
    localizeBlock();
}

#pragma mark - Store MomentInDayResult

- (void)saveMomentInDayResult:(ORKStepResult *)stepResult
{
    if ([stepResult.results count] > 0) {
        id  object = [stepResult.results lastObject];
        if ([object isKindOfClass:[ORKChoiceQuestionResult class]] == YES) {
            ORKChoiceQuestionResult  *result = (ORKChoiceQuestionResult *)object;
            NSString *answer = result.choiceAnswers.lastObject;
            if (answer != nil) {
                NSDictionary  *dictionary = @{
                                              kMomentInDayChoiceAnswerKey : answer,
                                              kMomentInDayQuestionTypeKey : @(result.questionType),
                                              kMomentInDayIdentifierKey   : result.identifier,
                                              kMomentInDayStartDateKey    : result.startDate,
                                              kMomentInDayEndDateKey      : result.endDate,
                                              kMomentInDayChoiceNoneKey   : @([kMomentInDayNoneChoice isEqualToString:answer])
                                              };
                NSUserDefaults  *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:dictionary forKey:kMomentInDayUserDefaultsKey];
                [defaults synchronize];
            }
        }
    }
}

#pragma mark - modify task

+ (ORKOrderedTask *)modifyTaskWithPreSurveyStepIfRequired:(ORKOrderedTask *)task andTitle:(NSString *)taskTitle
{
    APHAppDelegate  *appDelegate = (APHAppDelegate *)[UIApplication sharedApplication].delegate;
    NSDate          *lastCompletionDate = appDelegate.dataSubstrate.currentUser.taskCompletion;
    NSTimeInterval   numberOfSecondsSinceTaskCompletion = [[NSDate date] timeIntervalSinceDate: lastCompletionDate];
    NSDictionary  *stashedSurvey = [[NSUserDefaults standardUserDefaults] objectForKey:kMomentInDayUserDefaultsKey];
    BOOL noMeds = [stashedSurvey[kMomentInDayChoiceNoneKey] boolValue];
    NSTimeInterval minInterval = noMeds ? kMinimumAmountOfTimeToShowSurveyIfNoMeds : kMinimumAmountOfTimeToShowSurvey;
    
    ORKOrderedTask  *replacementTask = task;
    
    if (lastCompletionDate == nil || stashedSurvey == nil || numberOfSecondsSinceTaskCompletion > minInterval)
    {
        
        NSMutableArray  *stepQuestions = [NSMutableArray array];
        
        
        NSString *title = NSLocalizedString(@"We would like to understand how your performance on"
                                            " this activity could be affected by the timing of your medication.", @"Explanation of purpose of pre-activity medication timing survey.");
        ORKFormStep  *step = [[ORKFormStep alloc] initWithIdentifier:kMomentInDayStepIdentifier title:nil text:title];
        
        step.optional = NO;
        
        {
            NSString *itemText = NSLocalizedString(@"When was the last time you took any of your PARKINSON MEDICATIONS?",
                                                   @"Prompt for timing of medication in pre-activity medication timing survey.");
            

            
            NSString *notSureChoice = NSLocalizedString(@"Not sure", @"Timing option text in pre-activity medication timing survey for someone who is unsure of when medication was last taken.");
            
            NSString *formatMinutes = NSLocalizedString(@"%1$@-%2$@ minutes ago", @"Format for a time interval of %1$@ to %2$@ minutes ago where %1$@ is the localized number for the smaller value and %2$@ is the localized number for the larger value.");
            NSString *formatHours = NSLocalizedString(@"%1$@-%2$@ hours ago", @"Format for a time interval of %1$@ to %2$@ hours ago where %1$@ is the localized number for the smaller value and %2$@ is the localized number for the larger value.");
            NSString *formatMoreThanHoursAgo = NSLocalizedString(@"More than %@ hours ago", @"Timing option text in pre-activity medication timing survey for more than %@ hours ago.");
            
            NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
            [numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
            
            NSString * (^formattedInterval)(NSNumber *, NSNumber *, NSString *) = ^(NSNumber * minTime, NSNumber * maxTime, NSString *format){
                return [NSString stringWithFormat:format, [numberFormatter stringForObjectValue:minTime], [numberFormatter stringForObjectValue:maxTime]];
            };
            
            NSArray *choices = @[formattedInterval(@(0), @(30), formatMinutes),
                                 formattedInterval(@(30), @(60), formatMinutes),
                                 formattedInterval(@(1), @(2), formatHours),
                                 formattedInterval(@(2), @(4), formatHours),
                                 formattedInterval(@(4), @(8), formatHours),
                                 [NSString stringWithFormat:formatMoreThanHoursAgo, [numberFormatter stringForObjectValue:@(8)]],
                                 notSureChoice,
                                 kMomentInDayNoneChoice];

            ORKAnswerFormat  *format = [ORKTextChoiceAnswerFormat
                                        choiceAnswerFormatWithStyle:ORKChoiceAnswerStyleSingleChoice
                                                         textChoices:choices];
            
            ORKFormItem  *item = [[ORKFormItem alloc] initWithIdentifier:kMomentInDayFormat
                                                                   text:itemText
                                                           answerFormat:format];
            [stepQuestions addObject:item];
        }
        [step setFormItems:stepQuestions];
        
        NSMutableArray  *newSteps = [task.steps mutableCopy];
        if ([newSteps count] >= 1) {
            [newSteps insertObject:step atIndex:1];
        }
        replacementTask = [[ORKOrderedTask alloc] initWithIdentifier:taskTitle steps:newSteps];
    }
    return  replacementTask;
}


#pragma  mark  -  Task View Controller Delegate Methods

- (void)taskViewController:(ORKTaskViewController *)taskViewController didFinishWithReason:(ORKTaskViewControllerFinishReason)reason error:(nullable NSError *)error
{
    if (reason == ORKTaskViewControllerFinishReasonCompleted) {
        
        ORKResult  *stepResult = [[taskViewController result] resultForIdentifier:kMomentInDayStepIdentifier];
        
        if (stepResult != nil && [stepResult isKindOfClass:[ORKStepResult class]]) {
            [self saveMomentInDayResult:(ORKStepResult*)stepResult];
        }
        else {
        
            NSDictionary  *stashedSurvey = [[NSUserDefaults standardUserDefaults] objectForKey:kMomentInDayUserDefaultsKey];
            
            if (stashedSurvey != nil) {
                ORKChoiceQuestionResult  *aResult = [[ORKChoiceQuestionResult alloc] initWithIdentifier:kMomentInDayFormat];
                aResult.questionType = [stashedSurvey[kMomentInDayQuestionTypeKey] unsignedIntegerValue];
                aResult.startDate = stashedSurvey[kMomentInDayStartDateKey];
                aResult.endDate = stashedSurvey[kMomentInDayEndDateKey];
                aResult.choiceAnswers = @[ stashedSurvey[kMomentInDayChoiceAnswerKey] ];
                
                NSMutableArray  *stepResults = [NSMutableArray array];
                ORKStepResult  *aStepResult = [[ORKStepResult alloc] initWithStepIdentifier:kMomentInDayStepIdentifier results: @[ aResult ]];
                [stepResults addObject:aStepResult];
                for (ORKStepResult *stepResult in self.result.results) {
                    [stepResults addObject:stepResult];
                }
                self.stashedSteps = stepResults;
            }
        }
        APHAppDelegate *appDelegate = (APHAppDelegate *) [UIApplication sharedApplication].delegate;
        appDelegate.dataSubstrate.currentUser.taskCompletion = [NSDate date];
        
        [[UIView appearance] setTintColor:[UIColor appPrimaryColor]];
    }
    [super taskViewController:taskViewController didFinishWithReason:reason error:error];
}

#pragma  mark  -  View Controller Methods

-(ORKTaskResult * __nonnull)result
{
    ORKTaskResult  *taskResult = [super result];
    
    if (self.stashedSteps != nil) {
        [taskResult setResults:self.stashedSteps];
    }
    return  taskResult;
}

@end
