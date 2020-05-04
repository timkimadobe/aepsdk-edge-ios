/*
 Copyright 2020 Adobe. All rights reserved.

 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0
 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.

----
 XDM Property Swift Object Generated 2020-05-04 09:37:54.46006 -0700 PDT m=+1.683979090 by XDMTool

 Title			:	
 Description	:	
----
*/

import Foundation

struct IdentityMap {
	public var items: Items?

	enum CodingKeys: String, CodingKey {
		case items = "items"
	}	
}

extension IdentityMap:Encodable {
	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		if let unwrapped = items { try container.encode(unwrapped, forKey: .items) }
	}
}
