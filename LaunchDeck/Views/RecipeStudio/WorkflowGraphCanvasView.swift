import SwiftUI

struct WorkflowGraphCanvasView: View {
    @Bindable var studio: RecipeStudioStore
    @State private var scale = 1.0
    @State private var pendingOutput: (UUID, String)?

    private let nodeSize = CGSize(width: 210, height: 118)

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    grid
                    Canvas { context, _ in drawEdges(context: &context) }
                    ForEach(studio.workflow.nodes) { node in
                        nodeCard(node)
                            .frame(width: nodeSize.width, height: nodeSize.height)
                            .position(x: node.position.x + nodeSize.width / 2,
                                      y: node.position.y + nodeSize.height / 2)
                            .gesture(DragGesture().onChanged { value in
                                studio.updateSelected { selected in
                                    guard selected.id == node.id else { return }
                                    selected.position = .init(x: max(0, node.position.x + value.translation.width / scale),
                                                              y: max(0, node.position.y + value.translation.height / scale))
                                }
                            })
                    }
                }
                .frame(width: max(1600, geometry.size.width / scale),
                       height: max(1200, geometry.size.height / scale), alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .gesture(MagnifyGesture().onChanged { scale = min(2, max(0.45, $0.magnification)) })
        }
        .accessibilityLabel("Workflow graph canvas")
        .accessibilityHint("Use Outline mode for a complete keyboard-accessible workflow editor.")
    }

    private var grid: some View {
        Canvas { context, size in
            let spacing = 24.0
            var path = Path()
            stride(from: 0.0, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0.0, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 0.5)
        }
    }

    private func nodeCard(_ node: WorkflowNode) -> some View {
        let definition = WorkflowNodeCatalog.definition(for: node.kindIdentifier)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: definition?.systemImage ?? "square.dashed")
                Text(node.title).font(.headline).lineLimit(1)
                Spacer()
                Circle().fill(node.isEnabled ? .green : .secondary).frame(width: 7, height: 7)
            }
            Text(definition?.summary ?? node.kindIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            HStack {
                Menu("Inputs") {
                    ForEach(definition?.inputs ?? []) { port in
                        Button {
                            if let output = pendingOutput {
                                studio.connect(sourceNodeID: output.0, sourcePortID: output.1,
                                               targetNodeID: node.id, targetPortID: port.id)
                                pendingOutput = nil
                            }
                        } label: { Text(verbatim: "\(port.name) · \(port.valueType)") }
                    }
                }.disabled(pendingOutput == nil)
                Spacer()
                Menu("Outputs") {
                    ForEach(definition?.outputs ?? []) { port in
                        Button { pendingOutput = (node.id, port.id) } label: { Text(verbatim: "\(port.name) · \(port.valueType)") }
                    }
                }
            }.font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(studio.selectedNodeID == node.id ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: studio.selectedNodeID == node.id ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { studio.selectedNodeID = node.id }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.title), \(definition?.category.rawValue ?? "block") block")
    }

    private func drawEdges(context: inout GraphicsContext) {
        let nodes = Dictionary(uniqueKeysWithValues: studio.workflow.nodes.map { ($0.id, $0) })
        for edge in studio.workflow.edges {
            guard let source = nodes[edge.sourceNodeID], let target = nodes[edge.targetNodeID] else { continue }
            let start = CGPoint(x: source.position.x + nodeSize.width, y: source.position.y + nodeSize.height / 2)
            let end = CGPoint(x: target.position.x, y: target.position.y + nodeSize.height / 2)
            var path = Path(); path.move(to: start)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + max(50, (end.x - start.x) / 2), y: start.y),
                          control2: CGPoint(x: end.x - max(50, (end.x - start.x) / 2), y: end.y))
            context.stroke(path, with: .color(edge.id == studio.selectedEdgeID ? .accentColor : .secondary), lineWidth: 2)
        }
    }
}
