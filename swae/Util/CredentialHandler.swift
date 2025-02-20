//
//  CredentialHandler.swift
//  swae
//
//  Created by Suhail Saqan on 2/1/25.
//

import AuthenticationServices
import Foundation
import NostrSDK

final class CredentialHandler: NSObject, ASAuthorizationControllerDelegate {

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func checkCredentials() {
        let requests: [ASAuthorizationRequest] = [ASAuthorizationPasswordProvider().createRequest()]
        let authorizationController = ASAuthorizationController(authorizationRequests: requests)
        authorizationController.delegate = self
        authorizationController.performRequests()
    }

    func saveCredential(keypair: Keypair) {
        let npub = keypair.publicKey.npub
        let nsec = keypair.privateKey.nsec

        SecAddSharedWebCredential("swae.live" as CFString, npub as CFString, nsec as CFString, { error in
            if let error {
                print("⚠️ An error occurred while saving credentials: \(error)")
            }
        })
    }

    // MARK: - ASAuthorizationControllerDelegate
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASPasswordCredential else {
            return
        }

        Task {
            if let keypair = Keypair(nsec: credential.password) {
                appState.signIn(keypair: keypair, relayURLs: appState.relayReadPool.relays.map { $0.url })
            } else if let publicKey = PublicKey(npub: credential.password) {
                appState.signIn(publicKey: publicKey, relayURLs: appState.relayReadPool.relays.map { $0.url })
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("⚠️ Warning: authentication failed with error: \(error)")
    }
}
