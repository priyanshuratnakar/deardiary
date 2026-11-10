//
//  Authenticator.swift
//  Dear Diary
//
//  Asks macOS to check that the person at the Mac is its owner: Touch ID where
//  the Mac has it, an Apple Watch if one is set up to unlock the Mac, and the
//  Mac's own password otherwise. Dear Diary never sees a fingerprint or a
//  password. macOS draws the sheet, does the check and answers yes or no.
//

import Foundation
import LocalAuthentication

enum AuthenticationResult: Equatable {
    /// macOS checked, and it is the owner.
    case allowed
    /// The sheet was closed without an answer.
    case cancelled
    /// The check was made and did not pass.
    case failed
    /// This Mac has no way to check (it has no password set).
    case unavailable
}

protocol Authenticator: Sendable {
    /// True if this Mac can check who is using it.
    func isAvailable() -> Bool
    /// Asks. `reason` finishes the sentence macOS shows: "Dear Diary is trying to …".
    func authenticate(reason: String) async -> AuthenticationResult
}

/// The real check, made by macOS.
struct DeviceOwnerAuthenticator: Authenticator {
    func isAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(reason: String) async -> AuthenticationResult {
        // A fresh context each time, so an earlier yes is never reused.
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        do {
            let passed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return passed ? .allowed : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .passcodeNotSet:
                return .unavailable
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}
