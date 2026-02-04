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
                processChildSimply(child,
                                 hostObject: hostObject,
                                 currentClass: unwrappedCurrClass,
                                 initialClass: initialInClass)
            }
            mirror = m.superclassMirror
            currClass = unwrappedCurrClass.superclass()
        }
    }

    private static func processChildSimply(_ child: Mirror.Child,
                                          hostObject: AnyObject,
                                          currentClass: AnyClass,
                                          initialClass: AnyClass?) {
        // Безопасное извлечение данных без try-catch
        let childMirror = Mirror(reflecting: child)
        
        guard childMirror.displayStyle == .tuple else {
            return
        }
        
        // Получаем элементы tuple
        let children = Array(childMirror.children)
        guard children.count >= 2 else {
            return
        }
        
        // Извлекаем label
        let labelElement = children[0].value
        var label: String? = nil
        
        // Обрабатываем Optional<String>
        if let optionalString = labelElement as? String? {
            label = optionalString
        } else if let string = labelElement as? String {
            label = string
        } else {
            let mirror = Mirror(reflecting: labelElement)
            if mirror.displayStyle == .optional, let first = mirror.children.first {
                label = first.value as? String
            }
        }
        
        // Извлекаем value
        let valueElement = children[1].value
        var actualValue: Any? = nil
        
        // Проверяем опциональность value
        let valueMirror = Mirror(reflecting: valueElement)
        if valueMirror.displayStyle == .optional {
            if valueMirror.children.isEmpty {
                // nil - пропускаем
                return
            }
            // Извлекаем значение из Optional
            actualValue = valueMirror.children.first?.value
        } else {
            actualValue = valueElement
        }
        
        // Проверяем что значение не nil и является NSObject
        guard let unwrappedValue = actualValue,
              let nsObjectValue = unwrappedValue as? NSObject else {
            return
        }
        
        // Проверяем поддерживаемые типы
        guard (nsObjectValue is UIView) ||
              (nsObjectValue is CALayer) ||
              (nsObjectValue is UIViewController) ||
              (nsObjectValue is UIGestureRecognizer) else {
            return
        }
        
        // Очищаем label
        let cleanedLabel = label?.replacingOccurrences(of: "$__lazy_storage_$_", with: "") ?? ""
        guard !cleanedLabel.isEmpty else {
            return
        }
        
        // Создаем trace
        let ivarTrace = LookinIvarTrace()
        ivarTrace.hostObject = hostObject
        ivarTrace.hostClassName = makeDisplayClassName(superClass: currentClass, childClass: initialClass)
        ivarTrace.ivarName = cleanedLabel
        
        if (nsObjectValue === hostObject) {
            ivarTrace.relation = LookinIvarTraceRelationValue_Self
        } else if let hostView = hostObject as? UIView {
            var ivarLayer: CALayer? = nil
            if let layer = nsObjectValue as? CALayer {
                ivarLayer = layer
            } else if let view = nsObjectValue as? UIView {
                ivarLayer = view.layer
            }
            if let layer = ivarLayer, layer.superlayer === hostView.layer {
                ivarTrace.relation = "superview"
            }
        }
        nsObjectValue.lks_ivarTraces = (nsObjectValue.lks_ivarTraces ?? []) + [ivarTrace]
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
