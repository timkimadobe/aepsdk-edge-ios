//
// Copyright 2023 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.
//

@testable import AEPCore
import AEPEdge
import AEPEdgeIdentity
import AEPServices
import Foundation
import XCTest

enum JSON: Equatable {
    case object([String:JSON])
    case array([JSON])
    case string(String)
    case bool(Bool)
    case number(Double)
    case null
    
    static func ==(lhs: JSON, rhs: JSON) -> Bool {
        switch lhs {
        case .object(let leftDictionary):
            guard let rightDictionary: [String: JSON] = rhs.value() else {
                XCTFail(#"""
                        rhs is NOT [String: Any] and is not equal to lhs

                        lhs: \#(leftDictionary)
                        
                        rhs: \#(rhs)
                        """#)
                return false
            }
            if rightDictionary.count != leftDictionary.count {
                XCTFail(#"""
                        lhs and rhs (type: [String: Any]) counts do not match.
                        lhs count: \#(leftDictionary.count)
                        rhs count: \#(rightDictionary.count)
                        
                        lhs: \#(leftDictionary)
                        
                        rhs: \#(rightDictionary)
                        """#)
                return false
            }
            for (key, value) in leftDictionary {
                print("KEY: \(key)")
                XCTAssertEqual(value, rightDictionary[key])
            }
        case .array(let leftArray):
            guard let rightArray: [JSON] = rhs.value() else {
                XCTFail(#"""
                        rhs is NOT [Any] and is not equal to lhs

                        lhs: \#(leftArray)
                        
                        rhs: \#(rhs)
                        """#)
                return false
                
            }
            if rightArray.count != leftArray.count {
                XCTFail(#"""
                        lhs and rhs (type: [String]) counts do not match.
                        lhs count: \#(leftArray.count)
                        rhs count: \#(rightArray.count)
                        
                        lhs: \#(leftArray)
                        
                        rhs: \#(rightArray)
                        """#)
                return false
            }
            for index in leftArray.indices {
                print("INDEX: \(index)")
                XCTAssertEqual(leftArray[index], rightArray[index])
//                if array[index] != rhsArray[index] {
//                    XCTFail("\(array[index]) != \(rhsArray[index])")
//                    return false
//                }
            }
        case .string(let string):
            XCTAssertEqual(string, rhs.value() as String?, "original rhs: \(rhs)")
//            XCTAssertEqual(lhs, rhs.value() as String?)
//            return string == rhs.value() as String?
        case .bool(let bool):
            XCTAssertEqual(bool, rhs.value() as Bool?, "original rhs: \(rhs)")
//            return bool == rhs.value() as Bool?
        case .number(let number):
            XCTAssertEqual(number, rhs.value() as Double?, "original rhs: \(rhs)")
//            return number == rhs.value() as Double?
        case .null:
            guard case .null = rhs else {
                XCTFail(#"""
                        rhs is NOT nil and is not equal to lhs

                        lhs: \#(lhs)
                        
                        rhs: \#(rhs)
                        """#)
                return false
            }
        }
        return true
    }
    
    func value<T>() -> T? {
        switch self {
        case .object(let value):
            return value as? T
        case .array(let value):
            return value as? T
        case .bool(let value):
            return value as? T
        case .number(let value):
            return value as? T
        case .string(let value):
            return value as? T
        case .null:
            return nil
        }
    }
}

extension JSON : Codable {
    
    init(from decoder: Decoder) throws {
        
        let container = try decoder.singleValueContainer()
        
        if let object = try? container.decode([String: JSON].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSON].self) {
            self = .array(array)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid JSON value."
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        
        var container = encoder.singleValueContainer()
        
        switch self {
        case let .object(object):
            try container.encode(object)
        case let .array(array):
            try container.encode(array)
        case let .string(string):
            try container.encode(string)
        case let .bool(bool):
            try container.encode(bool)
        case let .number(number):
            try container.encode(number)
        case .null:
            try container.encodeNil()
        }
    }
}

class NetworkTestingDelegate: NetworkRequestDelegate {
    var testCaseCompletion: (HttpConnection) -> ()
    func handleNetworkResponse(httpConnection: AEPServices.HttpConnection) {
        print("Delegate received httpConnection: \(httpConnection)")
        testCaseCompletion(httpConnection)
    }
    init() {
        testCaseCompletion = { httpConnection in
            
        }
    }
}

/// This test class validates proper intergration with upstream services, specifically Edge Network
class UpstreamIntegrationTests: XCTestCase {
    private var edgeEnvironment: EdgeEnvironment = .prod
    private var edgeLocationHint: EdgeLocationHint? = nil
    
    private let testingDelegate = NetworkTestingDelegate()
    
    let LOG_SOURCE = "SampleFunctionalTests"
    
    let asyncTimeout: TimeInterval = 10

    override func setUp() {
        let networkService = IntegrationTestNetworkService()
        networkService.testingDelegate = testingDelegate
        ServiceProvider.shared.networkService = networkService
        
        // Extract Edge Network environment level from shell environment
        if let environment = EdgeEnvironment() {
            self.edgeEnvironment = environment
        }
        print("Using Edge Network environment: \(edgeEnvironment.rawValue)")
        // Extract Edge location hint from shell environment
        if let locationHint = EdgeLocationHint() {
            self.edgeLocationHint = locationHint
        }
        
        let waitForRegistration = CountDownLatch(1)
        MobileCore.setLogLevel(.trace)
        MobileCore.configureWith(appId: "94f571f308d5/6b1be84da76a/launch-023a1b64f561-development")
        MobileCore.registerExtensions([Identity.self, Edge.self], {
            print("Extensions registration is complete")
            waitForRegistration.countDown()
        })
        XCTAssertEqual(DispatchTimeoutResult.success, waitForRegistration.await(timeout: 2))
        
        // Set Edge location hint value if one is set for the test
        if edgeLocationHint != nil {
            print("Setting Edge location hint to: \(String(describing: edgeLocationHint?.rawValue))")
            Edge.setLocationHint(edgeLocationHint?.rawValue)
        }
        else {
            print("No preset Edge location hint is being used for this test.")
        }
    }
    
    public override func tearDown() {
        super.tearDown()

        // to revisit when AMSDK-10169 is available
        // wait .2 seconds in case there are unexpected events that were in the dispatch process during cleanup
        usleep(200000)
        EventHub.reset()
        UserDefaults.clearAll()
        FileManager.default.clearCache()
    }
    
    // TODO: create specific listeners for type: Edge + source: * (wildcard) and capture all the response handles for the test event
    // TODO: create specific listeners for error responses
    func registerEdgeLocationHintListener(_ listener: @escaping EventListener) {
        MobileCore.registerEventListener(type: FunctionalTestConst.EventType.EDGE, source: "locationHint:result", listener: listener)
    }
    
    /// Converts a JSON string into the provided type.
    ///
    /// NOTE: caller is reponsible for providing the correct casting type resulting JSON, otherwise decoding will fail
    func convertToJSON<T>(_ jsonString: String) -> T? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Unable to convert provided JSON string to Data: \(jsonString)")
            return nil
        }
        
        guard let jsonDictionary = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? T else {
            XCTFail("Unable to convert provided JSON string to JSON type \(T.self)")
            return nil
        }
        return jsonDictionary
    }
    
    func testJSONComparisonSystem() {
        let multiline3 = #"""
            {
              "assignees": null,
              "author": {
                "id": "MDQ6VXNlcjE5OTA4MDY=",
                "is_bot": false,
                "login": "G00fY2",
                "name": "Thomas Wirth"
              },
              "body": "Looks like a BoM was added for the Adobe dependencies: #402\r\n\r\nAny ETA when this will be available on [MavenCentral](https://central.sonatype.com/namespace/com.adobe.marketing.mobile)?",
              "closed": false,
              "closedAt": null,
              "comments": [
                {
                  "id": "IC_kwDOG1EAjc5XypUn",
                  "author": {
                    "login": "yangyansong-adbe"
                  },
                  "authorAssociation": "MEMBER",
                  "body": "@G00fY2 We're still finalizing something internally. We don't have an ETA at this point in time, but the release should be available very soon. I will keep you updated. \r\n\r\nThanks,\r\nYansong",
                  "createdAt": "2023-03-16T23:30:46Z",
                  "includesCreatedEdit": false,
                  "isMinimized": false,
                  "minimizedReason": "",
                  "reactionGroups": [],
                  "url": "https://github.com/adobe/aepsdk-core-android/issues/412#issuecomment-1472894247",
                  "viewerDidAuthor": false
                }
              ],
              "createdAt": "2023-03-16T13:11:19Z",
              "id": "I_kwDOG1EAjc5hAOEQ",
              "labels": [],
              "milestone": null,
              "number": 412,
              "reactionGroups": [],
              "state": "OPEN",
              "title": "When will the BoM be available?",
              "updatedAt": "2023-03-16T23:30:46Z",
              "url": "https://github.com/adobe/aepsdk-core-android/issues/412"
            }
        """#

        let multiline4 = #"""
          {
            "assignees": [],
            "author": {
              "id": "MDQ6VXNlcjE5OTA4MDY=",
              "is_bot": 0,
              "login": "G00fY2",
              "name": "Thomas Wirth"
            },
            "body": "Looks like a BoM was added for the Adobe dependencies: #402\r\n\r\nAny ETA when this will be available on [MavenCentral](https://central.sonatype.com/namespace/com.adobe.marketing.mobile)?",
            "closed": false,
            "closedAt": null,
            "comments": [
              {
                "id": "IC_kwDOG1EAjc5XypUn",
                "author": {
                  "login": "yangyansong-adbe"
                },
                "authorAssociation": "MEMBER",
                "body": "@G00fY2 We're still finalizing something internally. We don't have an ETA at this point in time, but the release should be available very soon. I will keep you updated. \r\n\r\nThanks,\r\nYansong",
                "createdAt": "2023-03-16T23:30:46Z",
                "includesCreatedEdit": false,
                "isMinimized": false,
                "minimizedReason": "",
                "reactionGroups": [],
                "url": "https://github.com/adobe/aepsdk-core-android/issues/412#issuecomment-1472894247",
                "viewerDidAuthor": false
              }
            ],
            "createdAt": "2023-03-16T13:11:19Z",
            "id": "I_kwDOG1EAjc5hAOEQ",
            "labels": [],
            "milestone": null,
            "number": 412,
            "reactionGroups": [],
            "state": "OPEN",
            "title": "When will the BoM be available?",
            "updatedAt": "2023-03-16T23:30:46Z",
            "url": "https://githu.com/adobe/aepsdk-core-android/issues/412"
          }
        """#
        
        let result = try? JSONDecoder().decode(JSON.self, from: multiline3.data(using: .utf8)!)
        let result2 = try? JSONDecoder().decode(JSON.self, from: multiline4.data(using: .utf8)!)

        XCTAssertEqual(result, result2)
//        print(result == result2)
    }

    // MARK: sample tests for the FunctionalTest framework usage
    func testSample_AssertUnexpectedEvents() {
        // Register a callback with the functional test network service to receive the HTTPConnection object when it's available
        // Setup
        let edgeRequestContentExpectation = XCTestExpectation(description: "Edge extension request content listener called")
        let networkResponseExpectation = XCTestExpectation(description: "Network request callback called")
        // Async testing methodology
        // test cases should fail quickly, if conditions are not met
        // all of a test case's conditions should be tried before the lock condition on a case is released
        // there are 2 main areas to test:
            // 1. the HTTP code, metadata values, and data types/related validation
            // 2. the logical content (is the event response what we expect for this type of event sent?
        
        /// HttpConnection has object `response.URL` which has value: https://obumobile5.data.adobedc.net/ee/v1/interact?configId=d936b4a4-8f13-4d8d-aabc-fcd1874b1ee5&requestId=159AEE9A-45B6-469E-B6FA-FBE506DA2E34
        /// This is the same as the one set in the edge configuration?
        /// only need to validate against this one
        // MARK: Network response assertions
        testingDelegate.testCaseCompletion = { httpConnection in
            print("SOURCE: testCaseCompletion: \(httpConnection)")
            print("data as string: \(httpConnection.responseString)")
            
            httpConnection.response?.url
            print("baseURL: \(httpConnection.response?.url?.host)")
            if httpConnection.response?.url?.host == "obumobile5.data.adobedc.net" {
                XCTAssertEqual(200, httpConnection.responseCode)
                networkResponseExpectation.fulfill()
            }
            
        }
        
        let validationJSON = #"""
        {
          "payload": [
            {
              "ttlSeconds" : 1800,
              "scope" : "Target",
              "hint" : "35"
            },
            {
              "ttlSeconds" : 1800,
              "scope" : "AAM",
              "hint" : "9"
            },
            {
              "ttlSeconds" : 1800,
              "scope" : "EdgeNetwork",
              "hint" : "or2"
            }
          ]
        }
        """#
        
        // MARK: Response Event assertions
        registerEdgeLocationHintListener() { event in
            XCTAssertNotNil(event)
            let data = event.data
            XCTAssertNotNil(data)
            guard let payloadArray = data?["payload"] as? [[String:Any]] else {
                XCTFail()
                return
            }
            print()
            let targetHint = payloadArray[0]
            guard let locationHintCorrectValue: [String:Any] = self.convertToJSON(validationJSON), let locationHintPayload = locationHintCorrectValue["payload"] as? [[String:Any]] else {
                XCTFail()
                return
            }
            
            // TODO: JSON dictionary compare
//            XCTAssertEqual(locationHintPayload, payloadArray)
            XCTAssertEqual("Target", targetHint["scope"] as? String)
            XCTAssertEqual(1800, targetHint["ttlSeconds"] as? Int)
//            XCTAssertEqual("35", targetHint["hint"] as? String)
            
            Log.debug(label: self.LOG_SOURCE, "LISTENER: \(String(describing: data))")
//            XCTAssertEqual(true, data?[MessagingConstants.Event.Data.Key.REFRESH_MESSAGES] as? Bool)
            edgeRequestContentExpectation.fulfill()
        }
        
        // test
        let experienceEvent = ExperienceEvent(xdm: ["xdmtest": "data"],
                                              data: ["data": ["test": "data"]])
        Edge.sendEvent(experienceEvent: experienceEvent, { (handles: [EdgeEventHandle]) in
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            guard let data = try? encoder.encode(handles) else {
//                self.dataContent = "failed to encode EdgeEventHandle"
                print("failed to encode EdgeEventHandle")
                return
            }
//            self.dataContent = String(data: data, encoding: .utf8) ?? "failed to encode JSON to string"
            let result = String(data: data, encoding: .utf8) ?? "failed to encode JSON to string"
//            print("HANDLE: \(result)")
            Log.debug(label: self.LOG_SOURCE, "HANDLE: \(result)")
            
        })
        
        // verify
        wait(for: [edgeRequestContentExpectation, networkResponseExpectation], timeout: asyncTimeout)
    }
}

/// Performs equivalence between two dictionaries using ``NSDictionary`` (ObjC) equivalence
/// See Apple docs on ``NSDictionary/isEqual(_:)``: https://developer.apple.com/documentation/foundation/nsdictionary/1415445-isequal
fileprivate func ==(lhs: [String: Any], rhs: [String: Any] ) -> Bool {
    return NSDictionary(dictionary: lhs).isEqual(to: rhs)
}
