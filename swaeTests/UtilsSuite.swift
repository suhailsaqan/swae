import Foundation
@testable import swae
import Testing

struct UtilsSuite {
    // Note: formatFullDuration test is locale-dependent, skipping for now
    // UUID.add(data:) tests require UUID extension that may not exist in Swae
    
    @Test
    func stringTrim() {
        #expect("  hello  ".trim() == "hello")
        #expect("\n\ttest\n".trim() == "test")
        #expect("nowhitespace".trim() == "nowhitespace")
    }
    
    @Test
    func sleepFunctionExists() async throws {
        // Just verify the sleep functions compile and run
        try await sleep(milliSeconds: 1)
        // Don't test sleep(seconds:) as it would slow down tests
    }
}
