//
//  EmojiArtViewController.swift
//  EmojiArt
//
//  Created by Konstantin Kotsarev on 25.01.2022.
//

import UIKit
import MobileCoreServices

class EmojiArtViewController: UIViewController, UIDropInteractionDelegate, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDragDelegate, UICollectionViewDropDelegate, UIPopoverPresentationControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate
{
    // MARK: - Camera
    
    @IBOutlet weak var cameraButton: UIBarButtonItem! {
        didSet {
            cameraButton.isEnabled = UIImagePickerController.isSourceTypeAvailable(.camera)
        }
    }
    
    @IBAction func takeBackgroundPhoto(_ sender: UIBarButtonItem) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [kUTTypeImage as String]
        picker.allowsEditing = true
        picker.delegate = self
        present(picker, animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.presentingViewController?.dismiss(animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = ((info[UIImagePickerController.InfoKey.editedImage] ?? info[UIImagePickerController.InfoKey.originalImage]) as? UIImage)?.scaled(by: 0.25) {
//            let url = image.storeLocallyAsJPEG(named: String(Date.timeIntervalSinceReferenceDate))
            if let imageData = image.jpegData(compressionQuality: 1.0) {
                emojiArtBackgroundImage = .local(imageData, image)
                documentChanged()
            } else {
                // TODO: alert user of bad camera input
            }
        }
        picker.presentingViewController?.dismiss(animated: true)
    }
    
    // MARK: - Navigation
    
    // here we prepare both for our Modal and Popover segues
    // and for our Embed Segue
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Show Document Info" {
            if let destination = segue.destination.contents as? DocumentInfoViewController {
                document?.thumbnail = emojiArtView.snapshot
                destination.document = document
                // if we're in a popover set ourselves as the delegate
                // so we can control the adaptation behavior to compact environments
                if let ppc = destination.popoverPresentationController {
                    ppc.delegate = self
                    // we could do other popover configuration here too
                }
            }
        } else if segue.identifier == "Embed Document Info" {
            // just grab onto the MVC so we can update it later
            embeddedDocInfo = segue.destination.contents as? DocumentInfoViewController
        }
    }
    
    // a Popover Segue adapts by default in horizontally compact environments
    // but we don't actually want that for our small popover
    // so we set the UIPopoverPresentantionController's delegate
    // to ourself in prepare(for segue:)
    // then implement this delegate method which returns
    // that the adaptaion style it should use is always .none
    // (i.e. never adapt)
    // if we wanted to, we could have looked at the traitCollection
    // to see what environment is being adapted to and made a decision from there
    
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
    
    // we allow view controllers that we've presented
    // to dismiss themselves by using Unwind Segue back to us
    // which will also close the document
    // the view controller we're unwinding from
    // is available in bySegue source
    // (we don't happen to need it, but we if we did ...)
    
    @IBAction func close(bySegue: UIStoryboardSegue) {
        close()
    }
    
    // we grab ahold of our embedded DocumentInfoViewController
    // during the prepare for that Embed Segue
    // we then keep it up to date as our document changes
    
    private var embeddedDocInfo: DocumentInfoViewController?
    
    // these layout constraints
    // allow us size our embedded DocumentInfoViewController
    // to its preferredContentSize
    // (see viewWillAppear below)
    
    @IBOutlet weak var embeddedDocInfoWidth: NSLayoutConstraint!
    @IBOutlet weak var embeddedDocInfoHeight: NSLayoutConstraint!
    
    // MARK: - Model
    
    var emojiArt: EmojiArt? {
        get {
            if let imageSource = emojiArtBackgroundImage {
                let emojis = emojiArtView.subviews.compactMap { $0 as? UILabel }.compactMap { EmojiArt.EmojiInfo(label: $0) }
                switch imageSource {
                case .remote(let url, _): return EmojiArt(url: url, emojis: emojis)
                case .local(let imageData, _): return EmojiArt(imageData: imageData, emojis: emojis)
                }
            }
            return nil
        }
        set {
            emojiArtBackgroundImage = nil
            emojiArtView.subviews.compactMap { $0 as? UILabel }.forEach { $0.removeFromSuperview() }
            let imageData = newValue?.imageData
            let image = (imageData != nil) ? UIImage(data: imageData!) : nil
            if let url = newValue?.url {
                imageFetcher = ImageFetcher() { (url, image) in
                    DispatchQueue.main.async {
                        if image == self.imageFetcher.backup {
                            self.emojiArtBackgroundImage = .local(imageData!, image)
                        } else {
                            self.emojiArtBackgroundImage = .remote(url, image)
                        }
                        newValue?.emojis.forEach {
                            let attributedText = $0.text.attributedString(withTextStyle: .body, ofSize: CGFloat($0.size))
                            self.emojiArtView.addLabel(with: attributedText, centeredAt: CGPoint(x: $0.x, y: $0.y))
                        }
                    }
                }
                imageFetcher.backup = image
                imageFetcher.fetch(url)
            } else if image != nil {
                emojiArtBackgroundImage = .local(imageData!, image!)
                newValue?.emojis.forEach {
                    let attributedText = $0.text.attributedString(withTextStyle: .body, ofSize: CGFloat($0.size))
                    self.emojiArtView.addLabel(with: attributedText, centeredAt: CGPoint(x: $0.x, y: $0.y))
                }
            }
        }
    }
    
    // MARK: - Document Handling
    
    var document: EmojiArtDocument?
    
//    @IBAction func save(_ sender: UIBarButtonItem? = nil) {
    func documentChanged() {
        document?.emojiArt = emojiArt
        if document?.emojiArt != nil {
            document?.updateChangeCount(.done)
        }
    }
    
    @IBAction func close(_ sender: UIBarButtonItem? = nil) {
        if let observer = emojiArtViewObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if document?.emojiArt != nil {
            document?.thumbnail = emojiArtView.snapshot
        }
        presentingViewController?.dismiss(animated: true) {
            self.document?.close { success in
                if let observer = self.documentObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
    
    private var documentObserver: NSObjectProtocol?
    private var emojiArtViewObserver: NSObjectProtocol?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if document?.documentState != .normal {
            documentObserver = NotificationCenter.default.addObserver(
                forName: UIDocument.stateChangedNotification,
                object: document,
                queue: OperationQueue.main,
                using: { notification in
                    print("document changed to \(self.document!.documentState)")
                    // if the document state changes to .normal
                    // (either because we just opened it or it finished autosaving)
                    // update the document in our embedded DocumentInfoViewController
                    // and also resize it to its preferredContentSize
                    if self.document!.documentState == .normal, let docInfoVC = self.embeddedDocInfo {
                        docInfoVC.document = self.document
                        self.embeddedDocInfoWidth.constant = docInfoVC.preferredContentSize.width
                        self.embeddedDocInfoHeight.constant = docInfoVC.preferredContentSize.height
                    }
                }
            )
            document?.open { success in
                if success {
                    self.title = self.document?.localizedName
                    self.emojiArt = self.document?.emojiArt
                    self.emojiArtViewObserver = NotificationCenter.default.addObserver(
                        forName: .EmojiArtViewDidChange, 
                        object: self.emojiArtView, 
                        queue: OperationQueue.main, 
                        using: { notification in
                            self.documentChanged()
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Storyboard
    
    @IBOutlet weak var dropZone: UIView! {
        didSet {
            dropZone.addInteraction(UIDropInteraction(delegate: self))
        }
    }
    
    @IBOutlet weak var scrollViewHeight: NSLayoutConstraint!
    @IBOutlet weak var scrollViewWidth: NSLayoutConstraint!
    
    @IBOutlet weak var scrollView: UIScrollView! {
        didSet {
            scrollView.minimumZoomScale = 0.1
            scrollView.maximumZoomScale = 5.0
            scrollView.delegate = self
            scrollView.addSubview(emojiArtView)
        }
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollViewHeight.constant = scrollView.contentSize.height
        scrollViewWidth.constant = scrollView.contentSize.width
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return emojiArtView
    }
    
    // MARK: - Emoji Art View
    
    lazy var emojiArtView = EmojiArtView()
    
    enum ImageSource {
        case remote(URL, UIImage)
        case local(Data, UIImage)
        
        var image: UIImage {
            switch self {
            case .remote(_, let image): return image
            case .local(_, let image): return image
            }
        }
    }
    
    var emojiArtBackgroundImage: ImageSource? {
        didSet {
            scrollView?.zoomScale = 1.0
            emojiArtView.backgroundImage = emojiArtBackgroundImage?.image
            let size = emojiArtBackgroundImage?.image.size ?? CGSize.zero
            emojiArtView.frame = CGRect(origin: CGPoint.zero, size: size)
            scrollView?.contentSize = size
            scrollViewHeight?.constant = size.height
            scrollViewWidth?.constant = size.width
            if let dropZone = self.dropZone, size.width > 0, size.height > 0 {
                scrollView?.zoomScale = max(dropZone.bounds.size.width / size.width, dropZone.bounds.size.height / size.height)
            }
        }
    }
    
    // MARK: - Emoji Collection View
    
    var emojis = "😀🎁✈️🎱🍎🐶🐝☕️🎼🚲♣️👨‍🎓✏️🌈🤡🎓👻☎️".map { String($0) }
    
    @IBOutlet weak var emojiCollectionView: UICollectionView! {
        didSet {
            emojiCollectionView.dataSource = self
            emojiCollectionView.delegate = self
            emojiCollectionView.dragDelegate = self
            emojiCollectionView.dropDelegate = self
            emojiCollectionView.dragInteractionEnabled = true
        }
    }
    
    private var font: UIFont {
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.preferredFont(forTextStyle: .body).withSize(64.0))
    }
    
    private var addingEmoji = false
    
    @IBAction func addEmoji() {
        addingEmoji = true
        emojiCollectionView.reloadSections(IndexSet(integer: 0))
    }
    
    // MARK: - UICollectionViewDataSource
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return emojis.count
        default: return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 1 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiCell", for: indexPath)
            if let emojiCell = cell as? EmojiCollectionViewCell {
                let text = NSAttributedString(string: emojis[indexPath.item], attributes: [.font:font])
                emojiCell.label.attributedText = text
            }
            return cell
        } else if addingEmoji {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiInputCell", for: indexPath)
            if let inputCell = cell as? TextFieldCollectionViewCell {
                inputCell.resignationHandler = { [weak self, unowned inputCell] in
                    if let text = inputCell.textField.text {
                        self?.emojis = (text.map { String($0) } + self!.emojis).uniquified
                    }
                    self?.addingEmoji = false
                    self?.emojiCollectionView.reloadData()
                }
            }
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AddEmojiButtonCell", for: indexPath)
            return cell
        }
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if addingEmoji && indexPath.section == 0 {
            return CGSize(width: 300, height: 80)
        } else {
            return CGSize(width: 80, height: 80)
        }
    }
    
    // MARK: - UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let inputCell = cell as? TextFieldCollectionViewCell {
            inputCell.textField.becomeFirstResponder()
        }
    }
    
    // MARK: - UICollectionViewDragDelegate
    
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        session.localContext = collectionView
        return dragItems(at: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        return dragItems(at: indexPath)
    }
    
    private func dragItems(at indexPath: IndexPath) -> [UIDragItem] {
        if !addingEmoji, let attributedString = (emojiCollectionView.cellForItem(at: indexPath) as? EmojiCollectionViewCell)?.label.attributedText {
            let dragItem = UIDragItem(itemProvider: NSItemProvider(object: attributedString))
            dragItem.localObject = attributedString
            return [dragItem]
        } else {
            return []
        }
    }
    
    // MARK: - UICollectionViewDropDelegate
    
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSAttributedString.self)
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if let indexPath = destinationIndexPath, indexPath.section == 1 {
            let isSelf = (session.localDragSession?.localContext as? UICollectionView) == collectionView
            return UICollectionViewDropProposal(operation: isSelf ? .move : .copy, intent: .insertAtDestinationIndexPath)            
        } else {
            return UICollectionViewDropProposal(operation: .cancel)
        }
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        performDropWith coordinator: UICollectionViewDropCoordinator
    ) {
        let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: 0, section: 0)
        for item in coordinator.items {
            if let sourceIndexPath = item.sourceIndexPath {
                if let attributedString = item.dragItem.localObject as? NSAttributedString {
                    collectionView.performBatchUpdates({ 
                        emojis.remove(at: sourceIndexPath.item)
                        emojis.insert(attributedString.string, at: destinationIndexPath.item)
                        collectionView.deleteItems(at: [sourceIndexPath])
                        collectionView.insertItems(at: [destinationIndexPath])
                    })
                    coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
                }
            } else {
                let placeholderContext = coordinator.drop(
                    item.dragItem,
                    to: UICollectionViewDropPlaceholder(insertionIndexPath: destinationIndexPath, reuseIdentifier: "DropPlaceholderCell")
                )
                item.dragItem.itemProvider.loadObject(ofClass: NSAttributedString.self) { (provider, error) in
                    DispatchQueue.main.async {
                        placeholderContext.commitInsertion(dataSourceUpdates: { insertionIndexPath in
                            if let attributedString = provider as? NSAttributedString {
                                self.emojis.insert(attributedString.string, at: insertionIndexPath.item)
                            } else {
                                placeholderContext.deletePlaceholder()
                            }
                        })
                    }
                }
            }
        }
    }
    
    // MARK: - UIDropInteractionDelegate
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSURL.self) && session.canLoadObjects(ofClass: UIImage.self)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }
    
    private var suppressBadURLWarnings = false
    
    private func presentBadURLWarning(for url: URL?) {
        if !suppressBadURLWarnings {
            let alert = UIAlertController(
                title: "Image Transfer Failed",
                message: "Couldn't transfer the dropped image from its source.",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(
                title: "Keep Warning",
                style: .default
            ))
            
            alert.addAction(UIAlertAction(
                title: "Stop Warning", 
                style: .destructive,
                handler: { action in
                    self.suppressBadURLWarnings = true
                }
            ))
            
            present(alert, animated: true)
        }
    }
    
    var imageFetcher: ImageFetcher!
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        imageFetcher = ImageFetcher() { (url, image) in
            DispatchQueue.main.async {
                if image == self.imageFetcher.backup {
                    if let imageData = image.jpegData(compressionQuality: 1.0) {
                        self.emojiArtBackgroundImage = .local(imageData, image)
                        self.documentChanged()
                    } else {
                        self.presentBadURLWarning(for: url)
                    }
                }
                self.emojiArtBackgroundImage = .remote(url, image)
                self.documentChanged()
            }
        }
        session.loadObjects(ofClass: NSURL.self) { nsurls in
            if let url = nsurls.first as? URL {
                self.imageFetcher.fetch(url)
            }
        }
        session.loadObjects(ofClass: UIImage.self) { images in
            if let image = images.first as? UIImage {
                self.imageFetcher.backup = image
            }
        }
    }
}

extension EmojiArt.EmojiInfo
{
    init?(label: UILabel) {
        if let attributedText = label.attributedText, let font = attributedText.font {
            x = Int(label.center.x)
            y = Int(label.center.y)
            text = attributedText.string
            size = Int(font.pointSize)
        } else {
            return nil
        }
    }
}
