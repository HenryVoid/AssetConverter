extension URL {
    func optimizedVideoURL() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        
        // 낮은 품질 요청을 위한 쿼리 파라미터 추가
        let qualityQuery = URLQueryItem(name: "quality", value: "540p")
        components?.queryItems = (components?.queryItems ?? []) + [qualityQuery]
        
        return components?.url ?? self
    }
} 