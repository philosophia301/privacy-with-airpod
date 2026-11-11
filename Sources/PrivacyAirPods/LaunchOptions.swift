import Foundation

/// 진단과 배포 확인용 실행 인자. 일반 사용자는 인자 없이 실행함.
enum LaunchOptions {
    /// 외장 화면 작업을 방해하지 않도록 보호 대상과 설정 창을 내장 화면으로 제한함.
    static let builtInOnly = ProcessInfo.processInfo.arguments.contains("--built-in-only")
    /// 실제 가림 창을 한 번 열어 마스크를 갱신하고 닫은 뒤 종료 코드로 결과를 알림. UI는 띄우지 않음.
    static let smokeTest = ProcessInfo.processInfo.arguments.contains("--smoke-test")
}
