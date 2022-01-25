//
//  EmojiArtView.swift
//  EmojiArt
//
//  Created by Konstantin Kotsarev on 25.01.2022.
//

import UIKit

class EmojiArtView: UIView 
{
    var backgroundImage: UIImage? { didSet { setNeedsDisplay() } }
    
    override func draw(_ rect: CGRect) {
        backgroundImage?.draw(in: bounds)
    }
}
