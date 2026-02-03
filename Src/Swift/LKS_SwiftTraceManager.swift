#if SHOULD_COMPILE_LOOKIN_SERVER

//
//  LKS_TraceManager+Extension.swift
//  LookinServer
//
//  Created by Shida Zhu on 2022/8/21.
//

import Foundation
import UIKit
#if SPM_LOOKIN_SERVER_ENABLED
import LookinServerBase
#endif

public class LKS_SwiftTraceManager: NSObject {
    @objc public static func swiftMarkIVars(ofObject hostObject: AnyObject) {
        var mirror: Mirror? = Mirror(reflecting: hostObject)
        var currClass: AnyClass? = type(of: hostObject)
        let initialInClass: AnyClass? = currClass
        
        while let m = mirror, let unwrappedCurrClass = currClass {
            m.children.forEach { child in
                // Безопасная обработка с помощью do-catch
                do {
                    try processChildSafely(child,
                                          hostObject: hostObject,
                                          currentClass: unwrappedCurrClass,
                                          initialClass: initialInClass)
                } catch {
                    // Игнорируем ошибки при обработке отдельных свойств
                    print("Warning: Failed to process child property: \(error)")
                }
            }
            mirror = m.superclassMirror
            currClass = unwrappedCurrClass.superclass()
        }
    }

    private static func processChildSafely(_ child: Mirror.Child,
                                          hostObject: AnyObject,
                                          currentClass: AnyClass,
                                          initialClass: AnyClass?) throws {
        // Пытаемся безопасно привести тип
        guard let childTuple = child as? (label: String?, value: Any) else {
            // Если не получается, пробуем альтернативный метод
            let childMirror = Mirror(reflecting: child)
            
            // Проверяем что это tuple
            guard childMirror.displayStyle == .tuple else {
                throw NSError(domain: "LookinServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Child is not a tuple"])
            }
            
            let children = Array(childMirror.children)
            guard children.count >= 2 else {
                throw NSError(domain: "LookinServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tuple doesn't have 2 elements"])
            }
            
            // Извлекаем label и value
            let labelElement = children[0].value
            let valueElement = children[1].value
            
            // Получаем label из Optional<String>
            var label: String? = nil
            if let optionalString = labelElement as? String? {
                label = optionalString
            } else if let string = labelElement as? String {
                label = string
            } else {
                // Дополнительная попытка через Mirror
                let labelMirror = Mirror(reflecting: labelElement)
                if labelMirror.displayStyle == .optional,
                   let firstChild = labelMirror.children.first,
                   let stringValue = firstChild.value as? String {
                    label = stringValue
                }
            }
            
            // Пропускаем если label nil
            guard let unwrappedLabel = label else {
                throw NSError(domain: "LookinServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Label is nil"])
            }
            
            // Пропускаем если value нельзя привести к NSObject
            guard let nsObjectValue = valueElement as? NSObject else {
                throw NSError(domain: "LookinServer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Value is not NSObject"])
            }
            
            // Продолжаем обработку с полученными значениями
            try continueProcessing(label: unwrappedLabel,
                                  value: nsObjectValue,
                                  hostObject: hostObject,
                                  currentClass: currentClass,
                                  initialClass: initialClass)
            return
        }
        
        // Оригинальная логика обработки
        let label: String? = childTuple.label?.replacingOccurrences(of: "$__lazy_storage_$_", with: "")
        let value = childTuple.value
        
        guard let nsObjectValue = value as? NSObject else {
            throw NSError(domain: "LookinServer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Value cannot be cast to NSObject"])
        }
        
        try continueProcessing(label: label ?? "",
                              value: nsObjectValue,
                              hostObject: hostObject,
                              currentClass: currentClass,
                              initialClass: initialClass)
    }

    private static func continueProcessing(label: String,
                                          value: NSObject,
                                          hostObject: AnyObject,
                                          currentClass: AnyClass,
                                          initialClass: AnyClass?) throws {
        guard (value is UIView) || (value is CALayer) || (value is UIViewController) || (value is UIGestureRecognizer) else {
            throw NSError(domain: "LookinServer", code: 6, userInfo: [NSLocalizedDescriptionKey: "Value is not a supported UI type"])
        }
        
        guard label.count > 0 else {
            throw NSError(domain: "LookinServer", code: 7, userInfo: [NSLocalizedDescriptionKey: "Label is empty"])
        }
        
        let ivarTrace = LookinIvarTrace()
        ivarTrace.hostObject = hostObject
        
        ivarTrace.hostClassName = makeDisplayClassName(superClass: currentClass, childClass: initialClass)
        
        ivarTrace.ivarName = label
        
        if (value === hostObject) {
            ivarTrace.relation = LookinIvarTraceRelationValue_Self
        } else if let hostView = hostObject as? UIView {
            var ivarLayer: CALayer? = nil
            if let layer = value as? CALayer {
                ivarLayer = layer
            } else if let view = value as? UIView {
                ivarLayer = view.layer
            }
            if let layer = ivarLayer, layer.superlayer === hostView.layer {
                ivarTrace.relation = "superview"
            }
        }
        value.lks_ivarTraces = (value.lks_ivarTraces ?? []) + [ivarTrace]
    }
    
    // 比如 superClass 可能是 UIView，而 childClass 可能是 UIButton
    private static func makeDisplayClassName(superClass: AnyClass, childClass: AnyClass?) -> String {
        let superName = NSStringFromClass(superClass)
        
        guard let childClass = childClass else {
            return superName
        }
        let childName = NSStringFromClass(childClass)
        if superName == childName {
            return superName
        }
        let superModule = queryModuleName(classname: superName)
        let childModule = queryModuleName(classname: childName)
        if superModule != nil, superModule == childModule {
            let shortSuperName = queryShortName(classname: superName)
            // ( UIKit.UIButton : UIView *)
            return "\(childName) : \(shortSuperName)"
        }
        return "\(childName) : \(superName)"
    }
    
    private static func queryModuleName(classname: String) -> String? {
        let parts = classname.components(separatedBy: ".")
        if parts.count != 2 {
            return nil
        }
        return parts[0]
    }
    
    /// 不包含 module name
    private static func queryShortName(classname: String) -> String {
        let parts = classname.components(separatedBy: ".")
        if parts.count != 2 {
            return classname
        }
        return parts[1]
    }
}

#endif /* SHOULD_COMPILE_LOOKIN_SERVER */
