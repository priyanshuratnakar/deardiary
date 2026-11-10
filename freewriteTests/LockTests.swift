//
//  LockTests.swift
//  freewriteTests
//
//  Checks the lock: when it closes, what opens it, when it asks by itself, and
//  what Settings may change. macOS's check is played by a script, so no test
//  asks for Touch ID or a password, and the clock is the test's own.
//

import Foundation
import Testing
@testable import freewrite

@Suite @MainActor struct LockSettingsTests {

    @Test func theLockIsOffUntilItIsSwitchedOn() {
        let box = LockBox(on: false)

        #expect(LockSettings(defaults: box.defaults).enabled == false)
        #expect(box.settings.afterMinutes == 5)
        #expect(box.settings.delayInWords == "5 minutes")
    }

    @Test func theChoicesAreSavedAndReadBack() {
        let box = LockBox(on: true)
        box.settings.stepDelay()

        let later = LockSettings(defaults: box.defaults)

        #expect(later.enabled)
        #expect(later.afterMinutes == 15)
    }

    @Test func eachClickStepsTheDelayAndComesRound() {
        let box = LockBox()
        var seen: [String] = []
        for _ in 0..<4 {
            box.settings.stepDelay()
            seen.append(box.settings.delayInWords)
        }

        #expect(seen == ["15 minutes", "30 minutes", "1 minute", "5 minutes"])
    }

    @Test func aSavedDelayThatIsNotAChoiceFallsBackToFiveMinutes() {
        let box = LockBox()
        box.defaults.set(7, forKey: "lock.afterMinutes")

        #expect(LockSettings(defaults: box.defaults).afterMinutes == 5)
    }
}

@Suite @MainActor struct AppLockTests {

    // MARK: - Off means off

    @Test func withTheLockOffNothingEverLocksAndNobodyIsAsked() async {
        let box = LockBox(on: false)
        let lock = box.lock()
        #expect(!lock.isLocked)

        lock.lockNow()
        lock.macSteppedAway()
        lock.appWentToBackground()
        box.minutesPass(600)
        lock.lockIfAwayTooLong()
        lock.appCameBack()
        lock.askIfJustLocked()
        await lock.unlock()
        await box.settle()

        #expect(!lock.isLocked)
        #expect(box.check.reasons.isEmpty)
    }

    // MARK: - Opening

    @Test func withTheLockOnDearDiaryOpensLocked() {
        #expect(LockBox().lock().isLocked)
    }

    @Test func theOwnerOpensIt() async {
        let box = LockBox()
        let lock = box.lock()
        box.check.answers = [.allowed]

        await lock.unlock()

        #expect(!lock.isLocked)
        #expect(lock.problem == nil)
        #expect(box.check.reasons == ["unlock your journal"])
    }

    @Test func aClosedSheetLeavesItLockedAndSaysNothing() async {
        let box = LockBox()
        let lock = box.lock()
        box.check.answers = [.cancelled]

        await lock.unlock()

        #expect(lock.isLocked)
        #expect(lock.problem == nil)
        #expect(!lock.isAsking)
    }

    @Test func aCheckThatDoesNotPassSaysSoAndCanBeTriedAgain() async {
        let box = LockBox()
        let lock = box.lock()
        box.check.answers = [.failed, .allowed]

        await lock.unlock()
        #expect(lock.isLocked)
        #expect(lock.problem == "Couldn't check that it's you. Try again.")

        await lock.unlock()
        #expect(!lock.isLocked)
        #expect(lock.problem == nil)
    }

    @Test func aMacWithNoPasswordIsNotKeptOutOfItsOwnDiary() async {
        let box = LockBox()
        let lock = box.lock()
        box.check.answers = [.unavailable]

        await lock.unlock()

        #expect(!lock.isLocked)
        #expect(lock.problem == "The lock needs a password on this Mac. Set one in System Settings, then turn the lock on.")
    }

    // MARK: - Closing

    @Test func lockNowLocksAndWaitsForAClick() async {
        let box = LockBox()
        let lock = await box.openLock()

        lock.lockNow()
        lock.askIfJustLocked()
        await box.settle()

        #expect(lock.isLocked)
        // Only the opening at the start of the test was asked for.
        #expect(box.check.reasons.count == 1)
    }

    @Test func theMacGoingToSleepLocks() async {
        let box = LockBox()
        let lock = await box.openLock()

        lock.macSteppedAway()

        #expect(lock.isLocked)
    }

    @Test func aShortTripToTheBackgroundDoesNotLock() async {
        let box = LockBox()
        let lock = await box.openLock()

        lock.appWentToBackground()
        box.minutesPass(4.9)
        lock.lockIfAwayTooLong()
        lock.appCameBack()

        #expect(!lock.isLocked)
    }

    @Test func theBackgroundLocksAfterTheChosenTimeEvenIfNobodyComesBack() async {
        let box = LockBox()
        let lock = await box.openLock()

        lock.appWentToBackground()
        box.minutesPass(5)
        lock.lockIfAwayTooLong()

        #expect(lock.isLocked)
    }

    @Test func theChosenTimeIsTheOneUsed() async {
        let box = LockBox()
        box.settings.afterMinutes = 1
        let lock = await box.openLock()

        lock.appWentToBackground()
        box.minutesPass(1)
        lock.appCameBack()
        await box.settle()

        #expect(lock.isLocked)
    }

    @Test func timeAwayIsCountedFromTheLastTripOnly() async {
        let box = LockBox()
        let lock = await box.openLock()

        lock.appWentToBackground()
        box.minutesPass(3)
        lock.appCameBack()
        box.minutesPass(30)   // in front, writing
        lock.appWentToBackground()
        box.minutesPass(3)
        lock.appCameBack()

        #expect(!lock.isLocked)
    }

    // MARK: - Asking by itself

    @Test func atLaunchItAsksOnceWithoutAClick() async {
        let box = LockBox()
        let lock = box.lock()
        box.check.answers = [.cancelled]

        lock.askIfJustLocked()
        await box.settle()
        lock.askIfJustLocked()
        await box.settle()

        #expect(lock.isLocked)
        #expect(box.check.reasons.count == 1)
    }

    @Test func comingBackToADiaryThatLockedWhileAwayAsksOnce() async {
        let box = LockBox()
        let lock = await box.openLock()
        lock.appWentToBackground()
        box.minutesPass(6)
        lock.lockIfAwayTooLong()
        box.check.answers = [.allowed]

        lock.appCameBack()
        await box.settle()

        #expect(!lock.isLocked)
        #expect(box.check.reasons.count == 2)
    }

    @Test func aSheetThatWasClosedDoesNotComeStraightBack() async {
        let box = LockBox()
        let lock = await box.openLock()
        lock.appWentToBackground()
        box.minutesPass(6)
        lock.appCameBack()          // locks, and asks once
        await box.settle()
        #expect(lock.isLocked)
        #expect(box.check.reasons.count == 2)

        // The sheet closing brings Dear Diary to the front again. That must not ask.
        lock.appCameBack()
        await box.settle()
        #expect(box.check.reasons.count == 2)

        // Leaving and coming back later does.
        lock.appWentToBackground()
        lock.appCameBack()
        await box.settle()
        #expect(box.check.reasons.count == 3)
    }

    // MARK: - Settings

    @Test func turningTheLockOffNeedsTheOwner() async {
        let box = LockBox()
        let lock = await box.openLock()

        box.check.answers = [.cancelled]
        await lock.setEnabled(false)
        #expect(box.settings.enabled)

        box.check.answers = [.failed]
        await lock.setEnabled(false)
        #expect(box.settings.enabled)
        #expect(lock.problem == "Couldn't check that it's you. Try again.")

        box.check.answers = [.allowed]
        await lock.setEnabled(false)
        #expect(!box.settings.enabled)
        #expect(!lock.isLocked)
        #expect(box.check.reasons.last == "turn off the lock")
    }

    @Test func turningTheLockOnDoesNotLockStraightAwayAndNeedsNoCheck() async {
        let box = LockBox(on: false)
        let lock = box.lock()

        await lock.setEnabled(true)

        #expect(box.settings.enabled)
        #expect(!lock.isLocked)
        #expect(box.check.reasons.isEmpty)
        // From now on it locks.
        lock.lockNow()
        #expect(lock.isLocked)
    }

    @Test func theLockCannotBeTurnedOnWhereTheMacCannotCheck() async {
        let box = LockBox(on: false)
        box.check.available = false
        let lock = box.lock()

        await lock.setEnabled(true)

        #expect(!box.settings.enabled)
        #expect(lock.problem == "The lock needs a password on this Mac. Set one in System Settings, then turn the lock on.")
    }

    @Test func theAppUnderTestNeverOpensLocked() {
        // The tests run inside the app itself. Its own lock must be off there.
        #expect(!LockSettings.shared.enabled)
        #expect(!AppLock.shared.isLocked)
    }
}
