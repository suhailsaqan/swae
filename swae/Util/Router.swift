//
//  Router.swift
//  gibbe
//
//  Created by Suhail Saqan on 10/2/24.
//

import SwiftUI

enum Route: Hashable {
    case Home
    case Live
    case Profile
    
    static func == (lhs: Route, rhs: Route) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}

class NavigationCoordinator: ObservableObject {
    @Published var path = [Route]()

    func push(route: Route) {
        guard route != path.last else {
            return
        }
        path.append(route)
    }
    
    func isAtRoot() -> Bool {
        return path.count == 0
    }

    func popToRoot() {
        path = []
    }
}
